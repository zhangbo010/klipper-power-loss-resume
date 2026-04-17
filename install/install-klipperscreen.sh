#!/usr/bin/env bash
# 在已安装 KlipperScreen 的机器上覆盖 PLR 相关文件（覆盖前自动备份）
# 用法: sudo bash install/install-klipperscreen.sh
# 环境变量（可选）: KLIPPERSCREEN_HOME — 未设置时尝试 ~/KlipperScreen、/home/pi/KlipperScreen
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "错误: $*" >&2; exit 1; }

effective_home() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    getent passwd "$SUDO_USER" | cut -d: -f6
  else
    echo "$HOME"
  fi
}
EH="$(effective_home)"

detect_klipperscreen_home() {
  local d
  for d in \
    "${KLIPPERSCREEN_HOME:-}" \
    "${EH}/KlipperScreen" \
    /home/pi/KlipperScreen \
    /usr/share/KlipperScreen; do
    [[ -z "$d" ]] && continue
    if [[ -f "$d/screen.py" ]] && [[ -d "$d/panels" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

[[ "$(id -u)" -eq 0 ]] || die "请使用 sudo 运行"

if [[ -z "${KLIPPERSCREEN_HOME:-}" ]]; then
  KS="$(detect_klipperscreen_home)" || die "未找到 KlipperScreen。请设置 KLIPPERSCREEN_HOME 为安装目录（含 screen.py、panels/）"
else
  KS="${KLIPPERSCREEN_HOME}"
fi

[[ -d "$KS" ]] || die "无效 KLIPPERSCREEN_HOME: $KS"

echo "==> KLIPPERSCREEN_HOME=$KS"

TS="$(date +%Y%m%d%H%M%S")
for f in screen.py panels/main_menu.py; do
  src="${REPO_ROOT}/klipperscreen/${f}"
  dst="${KS}/${f}"
  [[ -f "$src" ]] || die "缺少源文件: $src（请在克隆/解压后的本仓库根目录执行）"
  [[ -f "$dst" ]] && cp -a "$dst" "${dst}.bak.${TS}"
  install -m 0644 "$src" "$dst"
  echo "已安装: $dst"
done

echo "完成。请重启 KlipperScreen 服务。"
