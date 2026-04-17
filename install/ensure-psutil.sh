#!/usr/bin/env bash
# 为「Klipper 实际使用的 Python」安装 psutil（排错：No module named 'psutil'）
# 用法（在仓库根目录）:
#   export KLIPPER_HOME=/home/user/klipper   # 可选，未设则自动探测
#   bash install/ensure-psutil.sh
# 若需 sudo 提权（pip 写系统目录时）:
#   sudo bash install/ensure-psutil.sh
set -euo pipefail

die() { echo "错误: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

if [[ -z "${KLIPPER_HOME:-}" ]]; then
  KLIPPER_HOME="$(detect_klipper_home)" || {
    echo "请设置: export KLIPPER_HOME=/path/to/klipper"
    exit 1
  }
fi
export KLIPPER_HOME

KPY="$(detect_klipper_python)" || die "无法确定 Python"
echo "==> $KPY"

if "$KPY" -c "import psutil" 2>/dev/null; then
  echo "psutil 已安装，无需操作。"
  exit 0
fi

echo "正在安装 psutil 到该解释器..."
if [[ "$KPY" == *"/venv/bin/python"* ]] || [[ "$KPY" == *"/.venv/bin/python"* ]]; then
  if [[ "$(id -u)" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
    sudo -u "${SUDO_USER}" -- "$KPY" -m pip install psutil
  else
    "$KPY" -m pip install psutil
  fi
else
  if command -v apt-get >/dev/null; then
    apt-get update -qq && apt-get install -y python3-psutil
  else
    "$KPY" -m pip install psutil
  fi
fi

"$KPY" -c "import psutil" && echo "完成。请执行: sudo systemctl restart klipper"
