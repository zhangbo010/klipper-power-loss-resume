#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
静态测试：模拟 virtual_sdcard 的「Z 变化触发快照」与 power_loss_resume 的「弹窗 / get_info」判定。
不依赖 Klipper，仅验证与仓库内逻辑一致的条件与数据流。

运行（在仓库根目录；Debian 等无 python 命令时请用 python3）:
  python3 tests/test_plr_static.py -v
  python3 -m unittest tests/test_plr_static.py -v
"""

from __future__ import annotations

import json
import re
import unittest
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# 与 virtual_sdcard._maybe_plr_z_snapshot 一致的判定（抽成纯函数便于测试）
# ---------------------------------------------------------------------------


def maybe_plr_z_snapshot(
    z_now: float,
    last_z: Optional[float],
    epsilon: float = 1e-5,
) -> Tuple[bool, float]:
    """
    返回 (是否应调用 _save_power_loss_info, 新的 last_z)。
    首帧 last_z is None 时只建立基准，不触发保存。
    """
    if last_z is None:
        return False, z_now
    if abs(z_now - last_z) <= epsilon:
        return False, last_z
    return True, z_now


# ---------------------------------------------------------------------------
# 与 power_loss_resume.get_status / get_info 一致的有效续打判定
# ---------------------------------------------------------------------------


def plr_klipper_object_shows_resume(power_loss_info: Optional[Dict[str, Any]]) -> bool:
    """对应 get_status 里用于 objects 订阅的 power_loss_resume 布尔值。"""
    if power_loss_info is None or "power_loss_resume" not in power_loss_info:
        return False
    if (
        power_loss_info.get("file_path")
        and power_loss_info["file_path"] != ""
        and "print_stats" in power_loss_info
        and power_loss_info["print_stats"].get("filename")
    ):
        return bool(power_loss_info["power_loss_resume"])
    return False


def build_get_info_response(power_loss_info: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """对应 Moonraker 转发的 /printer/power_loss_resume/get_info 中的 power_loss_info 结构。"""
    if (
        power_loss_info is not None
        and "power_loss_resume" in power_loss_info
        and power_loss_info.get("file_path")
        and power_loss_info["file_path"] != ""
        and "print_stats" in power_loss_info
        and power_loss_info["print_stats"].get("filename")
    ):
        pr = bool(power_loss_info["power_loss_resume"])
    else:
        pr = False
    return {
        "power_loss_resume": pr,
        "file_path": power_loss_info["file_path"] if pr else None,
        "progress": power_loss_info.get("progress", 0) if pr else 0,
        "filename": (
            power_loss_info["print_stats"]["filename"] if pr else None
        ),
    }


def fluidd_popup_should_open(get_info_payload: Dict[str, Any]) -> bool:
    """Fluidd：watch powerLossResumeInfo，需 power_loss_resume 且 filename 非空。"""
    pi = get_info_payload
    return bool(pi.get("power_loss_resume")) and bool(pi.get("filename"))


def mainsail_show_dialog_hint(
    object_power_loss_resume: bool,
    get_info_payload: Dict[str, Any],
) -> bool:
    """Mainsail：showDialog 依赖对象订阅为真，且 get_info 填充 filename 等。"""
    if not object_power_loss_resume:
        return False
    return bool(get_info_payload.get("filename"))


# ---------------------------------------------------------------------------
# 极简 G 代码：仅更新模拟的 gcode_position[2]（Z）
# ---------------------------------------------------------------------------


def parse_z_from_g0_g1(line: str) -> Optional[float]:
    """从 G0/G1 行解析 Z（mm）；无数值则返回 None（保持调用方 Z 不变）。"""
    s = line.split(";")[0].strip().upper()
    if not s.startswith("G0") and not s.startswith("G1"):
        return None
    m = re.search(r"Z\s*([-+]?[0-9]*\.?[0-9]+(?:[Ee][-+]?[0-9]+)?)", s)
    if not m:
        return None
    return float(m.group(1))


@dataclass
class MockPrintState:
    """模拟 SD 打印中 gcode 状态（仅 XYZE 位置）。"""

    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    e: float = 0.0

    def gcode_position(self) -> List[float]:
        return [self.x, self.y, self.z, self.e]

    def apply_line(self, line: str) -> None:
        s = line.split(";")[0].strip().upper()
        if s.startswith("G0") or s.startswith("G1"):
            if "X" in s:
                mx = re.search(r"X\s*([-+]?[0-9]*\.?[0-9]+)", s)
                if mx:
                    self.x = float(mx.group(1))
            if "Y" in s:
                my = re.search(r"Y\s*([-+]?[0-9]*\.?[0-9]+)", s)
                if my:
                    self.y = float(my.group(1))
            mz = parse_z_from_g0_g1(line)
            if mz is not None:
                self.z = mz
            if "E" in s:
                me = re.search(r"E\s*([-+]?[0-9]*\.?[0-9]+)", s)
                if me:
                    self.e = float(me.group(1))


# ---------------------------------------------------------------------------
# 模拟一次「SD 行序列」：统计 Z 快照次数 + 构造续打 JSON
# ---------------------------------------------------------------------------


@dataclass
class SnapshotHarness:
    plr_snap_last_z: Optional[float] = None
    save_calls: int = 0
    last_info: Optional[Dict[str, Any]] = None

    def on_line_success(self, z: float) -> None:
        should_save, self.plr_snap_last_z = maybe_plr_z_snapshot(z, self.plr_snap_last_z)
        if should_save:
            self.save_calls += 1
            self.last_info = self._fake_save(z)

    def _fake_save(self, z: float) -> Dict[str, Any]:
        """模拟 _save_power_loss_info 写入后的内存态（仅弹窗所需字段）。"""
        return {
            "power_loss_resume": True,
            "file_path": "/tmp/gcodes/test.gcode",
            "progress": 0.35,
            "print_stats": {"filename": "test.gcode", "state": "printing"},
            "gcode_move": {"gcode_position": [110.0, 120.0, z, 1.0]},
        }


class TestZSnapshot(unittest.TestCase):
    def test_first_line_no_save(self):
        h = SnapshotHarness()
        h.on_line_success(0.2)
        self.assertEqual(h.save_calls, 0)
        self.assertAlmostEqual(h.plr_snap_last_z, 0.2)

    def test_same_z_no_save(self):
        h = SnapshotHarness()
        h.on_line_success(0.2)
        h.on_line_success(0.2)
        self.assertEqual(h.save_calls, 0)

    def test_layer_change_saves(self):
        h = SnapshotHarness()
        h.on_line_success(0.2)
        h.on_line_success(0.4)
        h.on_line_success(0.6)
        self.assertEqual(h.save_calls, 2)


class TestPopupLogic(unittest.TestCase):
    def test_empty_no_popup(self):
        self.assertFalse(plr_klipper_object_shows_resume(None))
        self.assertFalse(plr_klipper_object_shows_resume({}))
        self.assertFalse(
            plr_klipper_object_shows_resume({"power_loss_resume": True})
        )

    def test_valid_popup(self):
        info = {
            "power_loss_resume": True,
            "file_path": "/a/b.gcode",
            "print_stats": {"filename": "b.gcode"},
        }
        self.assertTrue(plr_klipper_object_shows_resume(info))
        gi = build_get_info_response(info)
        self.assertTrue(fluidd_popup_should_open(gi))
        self.assertTrue(mainsail_show_dialog_hint(True, gi))

    def test_power_loss_false_no_popup(self):
        info = {
            "power_loss_resume": False,
            "file_path": "/a/b.gcode",
            "print_stats": {"filename": "b.gcode"},
        }
        self.assertFalse(plr_klipper_object_shows_resume(info))


class TestGcodeParse(unittest.TestCase):
    def test_parse_z(self):
        self.assertAlmostEqual(parse_z_from_g0_g1("G1 Z0.4 F300"), 0.4)
        self.assertAlmostEqual(parse_z_from_g0_g1("g0 x1 y2 z5"), 5.0)
        self.assertIsNone(parse_z_from_g0_g1("G1 X10"))


class TestIntegratedScenario(unittest.TestCase):
    """模拟：读入多行 G 代码，仅在 Z 变化时增加快照次数；最后检查弹窗条件。"""

    def test_scenario(self):
        lines = [
            "G28",
            "G1 Z0.2 F300",
            "G1 X10 Y10 E0.1",
            "G1 Z0.4",
            "G1 X20",
            "G1 Z0.4",
        ]
        st = MockPrintState()
        h = SnapshotHarness()
        for line in lines:
            st.apply_line(line)
            h.on_line_success(st.z)

        # 首帧建立 Z 基准不保存，之后 Z 0.2 -> 0.4 至少一次快照
        self.assertGreaterEqual(h.save_calls, 1)
        self.assertIsNotNone(h.last_info)
        gi = build_get_info_response(h.last_info)
        self.assertTrue(fluidd_popup_should_open(gi))
        self.assertTrue(plr_klipper_object_shows_resume(h.last_info))


def run_demo_print_json() -> None:
    """打印一份示例 JSON，便于与网页 / curl 对照。"""
    info = {
        "power_loss_resume": True,
        "file_path": "/home/pi/printer_data/gcodes/demo.gcode",
        "progress": 0.42,
        "print_stats": {
            "filename": "demo.gcode",
            "state": "printing",
        },
    }
    gi = build_get_info_response(info)
    print("--- 示例 get_info（Moonraker 内层 power_loss_info）---")
    print(json.dumps({"power_loss_info": gi}, ensure_ascii=False, indent=2))
    print("fluidd_popup_should_open:", fluidd_popup_should_open(gi))
    print("klipper object resume:", plr_klipper_object_shows_resume(info))


if __name__ == "__main__":
    import sys

    if "--demo" in sys.argv:
        run_demo_print_json()
    else:
        unittest.main()
