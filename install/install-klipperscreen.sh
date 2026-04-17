#!/usr/bin/env bash
# 在已安装 KlipperScreen 的机器上覆盖 PLR 相关文件（覆盖前自动备份）
# 用法: sudo bash install/install-klipperscreen.sh
# 或交互安装: sudo bash install.sh
# 环境变量（可选）: KLIPPERSCREEN_HOME — 未设置时尝试 ~/KlipperScreen、/home/pi/KlipperScreen
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

die() { echo "错误: $*" >&2; exit 1; }

if [[ -z "${KLIPPERSCREEN_HOME:-}" ]]; then
  KS="$(detect_klipperscreen_home)" || die "未找到 KlipperScreen。请设置 KLIPPERSCREEN_HOME 为安装目录（含 screen.py、panels/）"
else
  KS="${KLIPPERSCREEN_HOME}"
fi

[[ -d "$KS" ]] || die "无效 KLIPPERSCREEN_HOME: $KS"

echo "==> KLIPPERSCREEN_HOME=$KS"

TS="$(date +%Y%m%d%H%M%S)"
run_copy() {
  local src="$1" dst="$2"
  if [[ -n "${SUDO_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]] && id -u "${SUDO_USER}" &>/dev/null; then
    if sudo -u "${SUDO_USER}" -- cp -a "$src" "$dst" 2>/dev/null; then
      return 0
    fi
  fi
  cp -a "$src" "$dst" || die "复制失败: $src -> $dst"
}
for f in screen.py panels/main_menu.py; do
  src="${REPO_ROOT}/klipperscreen/${f}"
  dst="${KS}/${f}"
  [[ -f "$src" ]] || die "缺少源文件: $src（请在克隆/解压后的本仓库根目录执行）"
  if [[ -f "$dst" ]]; then
    echo "==> 备份 ${dst}.bak.${TS}"
    if [[ -n "${SUDO_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]] && id -u "${SUDO_USER}" &>/dev/null; then
      sudo -u "${SUDO_USER}" -- cp -a "$dst" "${dst}.bak.${TS}" 2>/dev/null || cp -a "$dst" "${dst}.bak.${TS}" || die "备份失败"
    else
      cp -a "$dst" "${dst}.bak.${TS}" || die "备份失败"
    fi
  fi
  run_copy "$src" "$dst"
  echo "已安装: $dst"
done

echo "完成。请重启 KlipperScreen 服务。"
