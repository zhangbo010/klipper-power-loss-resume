#!/usr/bin/env bash
# 在已安装「标准 Klipper」的机器上安装 PLR（KIAUH / 官方脚本 / 发行版均可）
# 用法: 先 cd 到本仓库根目录（git clone 解压均可），再:
#   sudo bash install/install-klipper.sh
# 环境变量（可选，一般可省略，脚本会尝试自动发现）:
#   KLIPPER_HOME   Klipper 源码根目录（须含 klippy/extras）
#   PRINTER_DATA   Moonraker 配置目录（须含 config/），用于放置 plr.cfg.example
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${REPO_ROOT}/klipper"

die() { echo "错误: $*" >&2; exit 1; }

# sudo 时 HOME 常为 /root，改用实际登录用户的家目录
effective_home() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    getent passwd "$SUDO_USER" | cut -d: -f6
  else
    echo "$HOME"
  fi
}
EH="$(effective_home)"

# 自动探测 KLIPPER_HOME（标准安装常见路径，不依赖 FlyOS）
detect_klipper_home() {
  local d
  for d in \
    "${KLIPPER_HOME:-}" \
    "${EH}/klipper" \
    "${EH}/Klipper" \
    /home/pi/klipper \
    /usr/share/klipper; do
    [[ -z "$d" ]] && continue
    if [[ -d "$d/klippy/extras" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

# 自动探测 printer_data（Moonraker 默认）
detect_printer_data() {
  local d
  for d in \
    "${PRINTER_DATA:-}" \
    "${EH}/printer_data" \
    /home/pi/printer_data; do
    [[ -z "$d" ]] && continue
    if [[ -d "$d/config" ]]; then
      echo "$d"
      return 0
    fi
  done
  echo ""
}

[[ "$(id -u)" -eq 0 ]] || die "请使用 sudo 运行"

if [[ -z "${KLIPPER_HOME:-}" ]]; then
  KLIPPER_HOME="$(detect_klipper_home)" || die "未找到 Klipper 安装目录。请设置环境变量 KLIPPER_HOME 指向含 klippy/extras 的目录（例如 KIAUH 默认 ~/klipper）"
fi
EXTRAS="${KLIPPER_HOME}/klippy/extras"

if [[ -z "${PRINTER_DATA:-}" ]]; then
  PRINTER_DATA="$(detect_printer_data)"
fi
CFG_DIR=""
[[ -n "$PRINTER_DATA" ]] && CFG_DIR="${PRINTER_DATA}/config"

[[ -d "$EXTRAS" ]] || die "无效 KLIPPER_HOME: $KLIPPER_HOME（缺少 klippy/extras）"
[[ -d "$BUNDLE/klippy/extras" ]] || die "缺少本仓库内 klipper/klippy/extras（请在克隆/解压后的仓库根目录执行）"

command -v python3 >/dev/null || die "需要 python3"
python3 -c "import psutil" 2>/dev/null || {
  echo "缺少 Python 模块 psutil：pip3 install psutil 或 apt install python3-psutil"
  exit 1
}

echo "==> KLIPPER_HOME=$KLIPPER_HOME"
[[ -n "$PRINTER_DATA" ]] && echo "==> PRINTER_DATA=$PRINTER_DATA"

TS="$(date +%Y%m%d%H%M%S)"
backup() {
  local f="$1"
  [[ -f "$f" ]] && cp -a "$f" "${f}.bak.${TS}"
}

echo "==> 安装到 $EXTRAS"
backup "${EXTRAS}/virtual_sdcard.py"
backup "${EXTRAS}/power_loss_resume.py"
install -m 0644 "${BUNDLE}/klippy/extras/virtual_sdcard.py" "${EXTRAS}/virtual_sdcard.py"
install -m 0644 "${BUNDLE}/klippy/extras/power_loss_resume.py" "${EXTRAS}/power_loss_resume.py"

if [[ -n "$CFG_DIR" ]] && [[ -d "$CFG_DIR" ]]; then
  install -m 0644 "${REPO_ROOT}/config/plr.cfg.example" "${CFG_DIR}/plr.cfg.example" 2>/dev/null || true
  echo "==> 已放置示例: ${CFG_DIR}/plr.cfg.example"
elif [[ -f "${REPO_ROOT}/config/plr.cfg.example" ]]; then
  echo "提示: 未检测到 printer_data/config，请手动复制 config/plr.cfg.example 到打印机配置目录。"
fi

echo ""
echo "完成。请在 printer.cfg 中加入 [include plr.cfg]，将 plr.cfg.example 复制为 plr.cfg 并修改 power_pin 等，然后: sudo systemctl restart klipper"
