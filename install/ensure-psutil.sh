#!/usr/bin/env bash
# 为「Klipper 实际使用的 Python」安装 psutil（排错：No module named 'psutil'）
# 优先使用仓库 vendor/psutil 中的 wheel 离线安装，失败再 pip/ apt
# 用法（在仓库根目录）:
#   export KLIPPER_HOME=/home/user/klipper   # 可选，未设则自动探测
#   export KLIPPER_PYTHON=/usr/bin/python   # 可选；与 klipper.service 里 ExecStart 一致（FlyOS 常见）
#   bash install/ensure-psutil.sh
# 若需 sudo 提权:
#   sudo bash install/ensure-psutil.sh
set -euo pipefail

die() { echo "错误: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_PSUTIL="${REPO_ROOT}/vendor/psutil"

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

pip_install_psutil() {
  local use_vendor=0
  if [[ -d "$VENDOR_PSUTIL" ]] && compgen -G "${VENDOR_PSUTIL}/*.whl" >/dev/null 2>&1; then
    use_vendor=1
  fi

  run_pip() {
    if [[ "$(id -u)" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
      sudo -u "${SUDO_USER}" -- "$@"
    else
      "$@"
    fi
  }

  if [[ "$use_vendor" == "1" ]]; then
    echo "==> 尝试使用仓库内 vendor/psutil 离线安装…"
    if [[ "$KPY" == *"/venv/bin/python"* ]] || [[ "$KPY" == *"/.venv/bin/python"* ]]; then
      if run_pip "$KPY" -m pip install --no-index --find-links "$VENDOR_PSUTIL" psutil 2>/dev/null; then
        "$KPY" -c "import psutil" 2>/dev/null && return 0
      fi
    else
      if run_pip "$KPY" -m pip install --no-index --find-links "$VENDOR_PSUTIL" psutil 2>/dev/null; then
        "$KPY" -c "import psutil" 2>/dev/null && return 0
      fi
    fi
    echo "提示: 离线 wheel 与当前 Python/架构不匹配，改用在线或系统包…"
  fi

  echo "正在安装 psutil 到该解释器…"
  if [[ "$KPY" == *"/venv/bin/python"* ]] || [[ "$KPY" == *"/.venv/bin/python"* ]]; then
    run_pip "$KPY" -m pip install psutil
  else
    if command -v apt-get >/dev/null && [[ "$(id -u)" -eq 0 ]]; then
      apt-get update -qq && apt-get install -y python3-psutil || true
    fi
    if ! "$KPY" -c "import psutil" 2>/dev/null; then
      run_pip "$KPY" -m pip install psutil \
        || run_pip "$KPY" -m pip install psutil --break-system-packages
    fi
  fi
}

pip_install_psutil

"$KPY" -c "import psutil" || die "psutil 仍不可用，请检查网络或手动: $KPY -m pip install psutil"
echo "完成。请执行: sudo systemctl restart klipper"
