#!/usr/bin/env bash
# 将本仓库内 FlyOS 定制 Mainsail / Fluidd 静态资源部署到 Moonraker 使用的网页根目录
# 用法:
#   sudo INSTALL_WEB=both bash install/install-web.sh
#   INSTALL_WEB=mainsail|fluidd|both
# 可选环境变量: MAINSAIL_DIR  FLUIDD_DIR（未设置时自动探测）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
die() { echo "错误: $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "请使用 sudo 运行"

INSTALL_WEB="${INSTALL_WEB:-}"
[[ -n "$INSTALL_WEB" ]] || die "请设置 INSTALL_WEB=mainsail|fluidd|both"

case "$INSTALL_WEB" in
  mainsail|fluidd|both) ;;
  *) die "INSTALL_WEB 须为 mainsail|fluidd|both" ;;
esac

MS_SRC="${REPO_ROOT}/web/mainsail"
FD_SRC="${REPO_ROOT}/web/fluidd"

backup_and_copy() {
  local name="$1" src="$2" dst="$3"
  [[ -f "${src}/index.html" ]] || die "缺少源目录: $src（请使用含 web/ 的完整仓库）"
  [[ -n "$dst" ]] || die "未设置 ${name} 目标路径"
  local ts
  ts="$(date +%Y%m%d%H%M%S)"
  if [[ -d "$dst" ]] && [[ -f "${dst}/index.html" ]]; then
    echo "==> 备份 ${dst} -> ${dst}.bak.${ts}"
    cp -a "$dst" "${dst}.bak.${ts}"
  fi
  mkdir -p "$dst"
  echo "==> 部署 ${name}: ${src} -> ${dst}"
  cp -a "${src}/." "${dst}/"
}

deploy_mainsail() {
  local dst
  if [[ -n "${MAINSAIL_DIR:-}" ]]; then
    dst="$MAINSAIL_DIR"
  elif dst="$(detect_mainsail_dir)"; then
    :
  else
    return 1
  fi
  backup_and_copy "Mainsail" "$MS_SRC" "$dst"
  return 0
}

deploy_fluidd() {
  local dst
  if [[ -n "${FLUIDD_DIR:-}" ]]; then
    dst="$FLUIDD_DIR"
  elif dst="$(detect_fluidd_dir)"; then
    :
  else
    return 1
  fi
  backup_and_copy "Fluidd" "$FD_SRC" "$dst"
  return 0
}

if [[ "$INSTALL_WEB" == "mainsail" || "$INSTALL_WEB" == "both" ]]; then
  if [[ ! -f "${MS_SRC}/index.html" ]]; then
    [[ "$INSTALL_WEB" == "mainsail" ]] && die "缺少 ${MS_SRC}"
    echo "提示: 无 web/mainsail 源，跳过 Mainsail。"
  elif deploy_mainsail; then
    :
  else
    if [[ "$INSTALL_WEB" == "mainsail" ]]; then
      die "未找到 Mainsail 目录。请设置 MAINSAIL_DIR（须为含 index.html 的网页根）"
    fi
    echo "提示: 未探测到 Mainsail 安装目录，跳过。（仅使用 Fluidd 时可忽略）"
  fi
fi

if [[ "$INSTALL_WEB" == "fluidd" || "$INSTALL_WEB" == "both" ]]; then
  if [[ ! -f "${FD_SRC}/index.html" ]]; then
    [[ "$INSTALL_WEB" == "fluidd" ]] && die "缺少 ${FD_SRC}"
    echo "提示: 无 web/fluidd 源，跳过 Fluidd。"
  elif deploy_fluidd; then
    :
  else
    if [[ "$INSTALL_WEB" == "fluidd" ]]; then
      die "未找到 Fluidd 目录。请设置 FLUIDD_DIR（须为含 index.html 的网页根）"
    fi
    echo "提示: 未探测到 Fluidd 安装目录，跳过。（仅使用 Mainsail 时可忽略）"
  fi
fi

echo ""
echo "完成。请刷新浏览器缓存；若网页异常可恢复上述 .bak.* 目录。"
