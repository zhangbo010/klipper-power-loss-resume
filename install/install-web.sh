#!/usr/bin/env bash
# 将本仓库 git 内 web/mainsail、web/fluidd 部署到 Moonraker/nginx 使用的网页根目录。
# 若本机尚无对应目录（无 index.html），则安装到默认路径：~/mainsail、~/fluidd（不下载官方包）。
# 用法:
#   sudo INSTALL_WEB=both bash install/install-web.sh
#   INSTALL_WEB=mainsail|fluidd|both
# 可选环境变量: MAINSAIL_DIR  FLUIDD_DIR（未设置时先探测已有安装，再退回默认路径）
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
  [[ -f "${src}/index.html" ]] || die "缺少源目录: $src（请使用含 web/ 的完整 git 克隆）"
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
  # sudo 部署到用户家目录时归还属主，便于 Moonraker/nginx 以普通用户访问
  if [[ -n "${SUDO_USER:-}" ]] && [[ -d "$dst" ]]; then
    local eh
    eh="$(effective_home)"
    if [[ "$dst" == "$eh"/* ]] || [[ "$dst" == "$eh" ]]; then
      chown -R "${SUDO_USER}:${SUDO_USER}" "$dst" 2>/dev/null || true
    fi
  fi
}

deploy_mainsail() {
  local dst
  if [[ -n "${MAINSAIL_DIR:-}" ]]; then
    dst="$MAINSAIL_DIR"
  elif dst="$(detect_mainsail_dir)"; then
    :
  else
    dst="$(default_mainsail_install_dir)"
    echo "==> 本机未探测到已有 Mainsail，使用本仓库 web/mainsail 安装到: $dst"
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
    dst="$(default_fluidd_install_dir)"
    echo "==> 本机未探测到已有 Fluidd，使用本仓库 web/fluidd 安装到: $dst"
  fi
  backup_and_copy "Fluidd" "$FD_SRC" "$dst"
  return 0
}

if [[ "$INSTALL_WEB" == "mainsail" || "$INSTALL_WEB" == "both" ]]; then
  if [[ ! -f "${MS_SRC}/index.html" ]]; then
    [[ "$INSTALL_WEB" == "mainsail" ]] && die "缺少 ${MS_SRC}"
    echo "提示: 无 web/mainsail 源，跳过 Mainsail。"
  else
    deploy_mainsail
  fi
fi

if [[ "$INSTALL_WEB" == "fluidd" || "$INSTALL_WEB" == "both" ]]; then
  if [[ ! -f "${FD_SRC}/index.html" ]]; then
    [[ "$INSTALL_WEB" == "fluidd" ]] && die "缺少 ${FD_SRC}"
    echo "提示: 无 web/fluidd 源，跳过 Fluidd。"
  else
    deploy_fluidd
  fi
fi

echo ""
echo "完成。请刷新浏览器缓存；若网页异常可恢复上述 .bak.* 目录。"
echo ""
echo "说明：若需 http://IP/m/ 与 /f/ 同机切换，除静态文件外还须 nginx 双后端 + 80 分流："
echo "      sudo bash install/install-nginx-dual-ui.sh（见 docs/nginx-generic/README.md）"
