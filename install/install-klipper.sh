#!/usr/bin/env bash
# 在已安装「标准 Klipper」的机器上安装 PLR（KIAUH / 官方脚本 / 发行版均可）
# 用法: 先 cd 到本仓库根目录（git clone 解压均可），再:
#   sudo bash install/install-klipper.sh
# 或交互安装: sudo bash install.sh
# 环境变量（可选，一般可省略，脚本会尝试自动发现）:
#   KLIPPER_HOME   Klipper 源码根目录（须含 klippy/extras）
#   PRINTER_DATA   Moonraker 配置目录（须含 config/），用于放置 plr.cfg.example
#
# 说明：若以 sudo 运行且 home 在 NFS(root_squash)，root 可能无法读取 /home/user 下文件；
#       本脚本在存在 SUDO_USER 时用 sudo -u 该用户执行复制，避免静默失败。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUNDLE="${REPO_ROOT}/klipper"

die() { echo "错误: $*" >&2; exit 1; }

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

KPY="$(detect_klipper_python)" || die "无法找到 Klipper 使用的 Python（需 python3 或 \$KLIPPER_HOME/venv/bin/python）"
echo "==> Klipper Python: $KPY"
if ! "$KPY" -c "import psutil" 2>/dev/null; then
  echo "==> 未找到 psutil，正在安装（优先使用仓库 vendor/psutil 离线 wheel）…"
  bash "${SCRIPT_DIR}/ensure-psutil.sh" || die "psutil 安装失败"
fi

echo "==> KLIPPER_HOME=$KLIPPER_HOME"
[[ -n "$PRINTER_DATA" ]] && echo "==> PRINTER_DATA=$PRINTER_DATA"

TS="$(date +%Y%m%d%H%M%S)"

# 以「仓库与 Klipper 属主」身份复制，避免 NFS root_squash 下 root 读不了 /home/user
run_copy() {
  local src="$1" dst="$2"
  if [[ -n "${SUDO_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]] && id -u "${SUDO_USER}" &>/dev/null; then
    if sudo -u "${SUDO_USER}" -- cp -a "$src" "$dst" 2>/dev/null; then
      return 0
    fi
  fi
  cp -a "$src" "$dst" || die "复制失败: $src -> $dst（NFS root_squash 时勿把仓库放在仅 root 可读处；Klipper 在系统目录时需 root 可写）"
}

backup_if_exists() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  echo "==> 备份 ${f} -> ${f}.bak.${TS}"
  if [[ -n "${SUDO_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]] && id -u "${SUDO_USER}" &>/dev/null; then
    if sudo -u "${SUDO_USER}" -- cp -a "$f" "${f}.bak.${TS}" 2>/dev/null; then
      return 0
    fi
  fi
  cp -a "$f" "${f}.bak.${TS}" || die "备份失败: $f"
}

echo "==> 安装到 $EXTRAS"
for name in virtual_sdcard.py power_loss_resume.py; do
  src="${BUNDLE}/klippy/extras/${name}"
  dst="${EXTRAS}/${name}"
  [[ -f "$src" ]] || die "缺少源文件: $src"
  backup_if_exists "$dst"
  echo "==> 写入 ${name}"
  run_copy "$src" "$dst"
done

if [[ -n "$CFG_DIR" ]] && [[ -d "$CFG_DIR" ]]; then
  ex="${REPO_ROOT}/config/plr.cfg.example"
  if [[ -f "$ex" ]]; then
    echo "==> 放置 plr.cfg.example 到 ${CFG_DIR}/"
    if [[ -n "${SUDO_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]] && id -u "${SUDO_USER}" &>/dev/null; then
      sudo -u "${SUDO_USER}" -- cp -a "$ex" "${CFG_DIR}/plr.cfg.example" 2>/dev/null || \
        cp -a "$ex" "${CFG_DIR}/plr.cfg.example" 2>/dev/null || \
        echo "提示: 无法自动写入 plr.cfg.example，请手动复制" >&2
    else
      cp -a "$ex" "${CFG_DIR}/plr.cfg.example" 2>/dev/null || echo "提示: 无法自动写入 plr.cfg.example，请手动复制" >&2
    fi
    [[ -f "${CFG_DIR}/plr.cfg.example" ]] && echo "==> 已放置示例: ${CFG_DIR}/plr.cfg.example"
  fi
elif [[ -f "${REPO_ROOT}/config/plr.cfg.example" ]]; then
  echo "提示: 未检测到 printer_data/config，请手动复制 config/plr.cfg.example 到打印机配置目录。"
fi

echo ""
echo "完成。请在 printer.cfg 中加入 [include plr.cfg]，将 plr.cfg.example 复制为 plr.cfg 并修改 power_pin 等，然后: sudo systemctl restart klipper"
