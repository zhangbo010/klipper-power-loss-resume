#!/usr/bin/env bash
# PLR 交互安装：依赖检查 → 确认路径 → 安装 Klipper 插件 → 可选 KlipperScreen
# 用法（在仓库根目录）:
#   bash install.sh
# 若当前非 root，会自动以 sudo 重新执行本脚本。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INST="${ROOT}/install"
# shellcheck source=install/common.sh
source "${INST}/common.sh"

die() { echo "错误: $*" >&2; exit 1; }

if [[ "$(id -u)" -ne 0 ]]; then
  echo "将使用 sudo 提权以写入 Klipper / KlipperScreen 目录…"
  exec sudo bash "$0" "$@"
fi

[[ -d "${ROOT}/klipper/klippy/extras" ]] || die "请在克隆后的仓库根目录执行（缺少 klipper/klippy/extras）"

echo ""
echo "======== Klipper 断电续打（PLR）交互安装 ========"
echo ""

# --- 依赖 psutil ---
if ! command -v python3 >/dev/null; then
  die "未找到 python3，请先安装。"
fi

if ! python3 -c "import psutil" 2>/dev/null; then
  echo "未检测到 Python 模块 psutil（Klipper 续打需要）。"
  read -r -p "是否使用 apt 安装 python3-psutil？[Y/n] " _ps
  if [[ -z "${_ps}" ]] || [[ "${_ps}" == [Yy]* ]]; then
    if command -v apt-get >/dev/null; then
      apt-get update -qq && apt-get install -y python3-psutil
    else
      echo "当前系统无 apt-get，请手动执行: pip3 install psutil（与 Klipper 所用 Python 一致）"
      exit 1
    fi
  else
    die "请先安装 psutil 后重新运行本脚本。"
  fi
fi
python3 -c "import psutil" 2>/dev/null || die "psutil 仍不可用，请检查后重试。"

# --- Klipper / printer_data 路径 ---
KH=""
PD=""
if KH_TRY="$(detect_klipper_home)"; then
  KH="$KH_TRY"
else
  KH=""
fi
PD="$(detect_printer_data)"

echo "自动探测结果："
echo "  KLIPPER_HOME=${KH:-（未找到）}"
echo "  PRINTER_DATA=${PD:-（未找到）}"
echo ""
echo "  [1] 使用上述路径（若某项未找到，稍后可手动输入）"
echo "  [2] 手动输入 KLIPPER_HOME 与 PRINTER_DATA"
read -r -p "请选择 [1/2]（默认 1）: " _path_choice
_path_choice="${_path_choice:-1}"

unset KLIPPER_HOME PRINTER_DATA
case "${_path_choice}" in
  2)
    read -r -p "KLIPPER_HOME（须含 klippy/extras）: " KLIPPER_HOME
    read -r -p "PRINTER_DATA（可留空，须含 config/）: " PRINTER_DATA
    ;;
  *)
    if [[ -n "$KH" ]]; then
      KLIPPER_HOME="$KH"
    else
      read -r -p "未探测到 Klipper，请手动输入 KLIPPER_HOME: " KLIPPER_HOME
    fi
    if [[ -n "$PD" ]]; then
      PRINTER_DATA="$PD"
    else
      read -r -p "未探测到 printer_data，可留空；若需自动放置 plr 示例请输入路径: " PRINTER_DATA
    fi
    ;;
esac

[[ -z "${KLIPPER_HOME:-}" ]] && die "必须设置有效的 KLIPPER_HOME"
[[ -d "${KLIPPER_HOME}/klippy/extras" ]] || die "无效的 KLIPPER_HOME: $KLIPPER_HOME"

export KLIPPER_HOME
if [[ -n "${PRINTER_DATA:-}" ]]; then
  export PRINTER_DATA
else
  unset PRINTER_DATA
fi

echo ""
echo ">>> 正在安装 Klipper 插件 …"
bash "${INST}/install-klipper.sh"

# --- 可选 KlipperScreen ---
echo ""
read -r -p "是否安装 KlipperScreen 补丁（续打入口）？[y/N] " _ks
if [[ "${_ks}" == [yY]* ]]; then
  unset KLIPPERSCREEN_HOME
  KS=""
  if KS_TRY="$(detect_klipperscreen_home)"; then
    KS="$KS_TRY"
  fi
  echo "探测到 KlipperScreen: ${KS:-（未找到）}"
  read -r -p "使用该路径？[Y/n/手动输入 m] " _ksc
  _ksc="${_ksc:-Y}"
  case "${_ksc}" in
    [Mm]*)
      read -r -p "KLIPPERSCREEN_HOME: " KLIPPERSCREEN_HOME
      export KLIPPERSCREEN_HOME
      ;;
    [Nn]*)
      read -r -p "KLIPPERSCREEN_HOME: " KLIPPERSCREEN_HOME
      export KLIPPERSCREEN_HOME
      ;;
    *)
      if [[ -n "$KS" ]]; then
        export KLIPPERSCREEN_HOME="$KS"
      else
        read -r -p "请手动输入 KLIPPERSCREEN_HOME: " KLIPPERSCREEN_HOME
        export KLIPPERSCREEN_HOME
      fi
      ;;
  esac
  [[ -n "${KLIPPERSCREEN_HOME:-}" ]] || die "未设置 KLIPPERSCREEN_HOME"
  [[ -f "${KLIPPERSCREEN_HOME}/screen.py" ]] || die "无效的 KLIPPERSCREEN_HOME: $KLIPPERSCREEN_HOME"
  echo ""
  echo ">>> 正在安装 KlipperScreen 补丁 …"
  bash "${INST}/install-klipperscreen.sh"
fi

echo ""
echo "======== 安装步骤已完成 ========"
echo "请手动完成："
echo "  1. 将 ${PRINTER_DATA:-printer_data}/config/plr.cfg.example 复制为 plr.cfg（若尚未复制），按主板修改 power_pin 等"
echo "  2. 在 printer.cfg 中加入: [include plr.cfg]"
echo "  3. sudo systemctl restart klipper"
echo "  4. 若已装 KlipperScreen 补丁，请重启对应服务（如 sudo systemctl restart KlipperScreen）"
echo ""
