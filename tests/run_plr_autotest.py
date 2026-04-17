#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
一键自动测试（无需 Klipper）：
  1) 运行 tests/test_plr_static.py 全部 unittest（含对 examples/plr_motion_test.gcode 的解析）
  2) 打印示例 gcode 的 Z 快照次数与弹窗判定摘要

在仓库根目录执行:
  python3 tests/run_plr_autotest.py
  python3 tests/run_plr_autotest.py --summary-only
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_unittest_verbose() -> int:
    return subprocess.call(
        [sys.executable, "-m", "unittest", "tests.test_plr_static", "-v"],
        cwd=str(ROOT),
    )


def print_gcode_summary() -> None:
    sys.path.insert(0, str(ROOT))
    from tests.test_plr_static import (
        build_get_info_response,
        fluidd_popup_should_open,
        plr_klipper_object_shows_resume,
        simulate_gcode_file,
    )

    gcode = ROOT / "examples" / "plr_motion_test.gcode"
    if not gcode.is_file():
        print("未找到 examples/plr_motion_test.gcode，跳过摘要。")
        return
    h = simulate_gcode_file(gcode)
    gi = build_get_info_response(h.last_info)
    print()
    print("=== examples/plr_motion_test.gcode 模拟结果 ===")
    print("  Z 快照次数 (save_calls):", h.save_calls)
    print("  Klipper 对象可续打:", plr_klipper_object_shows_resume(h.last_info))
    print("  get_info payload:", gi)
    print("  Fluidd 弹窗条件:", fluidd_popup_should_open(gi))


def main() -> int:
    ap = argparse.ArgumentParser(description="PLR 静态自动测试")
    ap.add_argument(
        "--summary-only",
        action="store_true",
        help="不跑 unittest，只打印示例 gcode 模拟摘要",
    )
    args = ap.parse_args()

    if args.summary_only:
        print_gcode_summary()
        return 0

    print(">>> unittest tests.test_plr_static -v")
    rc = run_unittest_verbose()
    if rc != 0:
        return rc
    print_gcode_summary()
    print()
    print("全部通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
