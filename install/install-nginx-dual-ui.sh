#!/usr/bin/env bash
# 按「双后端 + 80 分流」机制部署 nginx（路径/端口适配常见 Klipper 主机，非照搬 FlyOS 固定目录）
# 用法: sudo bash install/install-nginx-dual-ui.sh
# 环境变量见 docs/nginx-generic/README.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

die() { echo "错误: $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "请使用 sudo 运行"

TMPL="${SCRIPT_DIR}/nginx-templates"
[[ -d "$TMPL" ]] || die "缺少模板目录: $TMPL"

FD_ROOT=""
MS_ROOT=""
if [[ -n "${FLUIDD_DIR:-}" ]]; then
  FD_ROOT="$FLUIDD_DIR"
elif FD_ROOT="$(detect_fluidd_dir)"; then
  :
else
  die "未找到 Fluidd 静态根（须含 index.html）。请先安装 Fluidd 或设置 FLUIDD_DIR=..."
fi

if [[ -n "${MAINSAIL_DIR:-}" ]]; then
  MS_ROOT="$MAINSAIL_DIR"
elif MS_ROOT="$(detect_mainsail_dir)"; then
  :
else
  die "未找到 Mainsail 静态根（须含 index.html）。请先安装 Mainsail 或设置 MAINSAIL_DIR=..."
fi

case "${FD_ROOT}" in *'#'*|*'&'*) die "FLUIDD 路径含 # 或 &，请改用无特殊字符的路径或手工编辑生成后的配置" ;; esac
case "${MS_ROOT}" in *'#'*|*'&'*) die "MAINSAIL 路径含 # 或 &，请改用无特殊字符的路径或手工编辑生成后的配置" ;; esac

MR_PORT="${MOONRAKER_PORT:-}"
if [[ -z "$MR_PORT" ]]; then
  if MR_TRY="$(detect_moonraker_port 2>/dev/null)"; then
    MR_PORT="$MR_TRY"
  else
    MR_PORT="7125"
    echo "提示: 未从 printer_data/config/moonraker.conf 解析到 [server] port，使用默认 7125。可设置 MOONRAKER_PORT=..."
  fi
fi
[[ "$MR_PORT" =~ ^[0-9]+$ ]] || die "无效的 MOONRAKER_PORT: $MR_PORT"

FLUIDD_PORT="${PLR_FLUIDD_PORT:-9080}"
MAINSAIL_PORT="${PLR_MAINSAIL_PORT:-9081}"
[[ "$FLUIDD_PORT" =~ ^[0-9]+$ ]] || die "无效的 PLR_FLUIDD_PORT"
[[ "$MAINSAIL_PORT" =~ ^[0-9]+$ ]] || die "无效的 PLR_MAINSAIL_PORT"
[[ "$FLUIDD_PORT" == "$MAINSAIL_PORT" ]] && die "PLR_FLUIDD_PORT 与 PLR_MAINSAIL_PORT 不能相同"

case "${PLR_DEFAULT_UI:-fluidd}" in
  mainsail|m|Mainsail)
    DEF_PORT="$MAINSAIL_PORT"
    ;;
  fluidd|f|Fluidd|"")
    DEF_PORT="$FLUIDD_PORT"
    ;;
  *)
    die "PLR_DEFAULT_UI 须为 fluidd 或 mainsail"
    ;;
esac

subst_write() {
  local src="$1" dst="$2"
  sed \
    -e "s#__FLUIDD_ROOT__#${FD_ROOT}#g" \
    -e "s#__MAINSAIL_ROOT__#${MS_ROOT}#g" \
    -e "s#__FLUIDD_BACKEND_PORT__#${FLUIDD_PORT}#g" \
    -e "s#__MAINSAIL_BACKEND_PORT__#${MAINSAIL_PORT}#g" \
    -e "s#__MOONRAKER_PORT__#${MR_PORT}#g" \
    -e "s#__DEFAULT_BACKEND_PORT__#${DEF_PORT}#g" \
    "$src" >"$dst"
}

OUTD="/etc/nginx/sites-available"
mkdir -p "$OUTD"

subst_write "${TMPL}/backend-fluidd.conf.template" "${OUTD}/plr-backend-fluidd.conf"
subst_write "${TMPL}/backend-mainsail.conf.template" "${OUTD}/plr-backend-mainsail.conf"
subst_write "${TMPL}/port80-gateway.conf.template" "${OUTD}/plr-gateway-80.conf"

chmod 0644 "${OUTD}/plr-backend-fluidd.conf" "${OUTD}/plr-backend-mainsail.conf" "${OUTD}/plr-gateway-80.conf"

echo ""
echo "已生成:"
echo "  ${OUTD}/plr-backend-fluidd.conf   (listen ${FLUIDD_PORT}, root ${FD_ROOT})"
echo "  ${OUTD}/plr-backend-mainsail.conf (listen ${MAINSAIL_PORT}, root ${MS_ROOT})"
echo "  ${OUTD}/plr-gateway-80.conf      (listen 80 → /f/ /m/，默认 / → ${DEF_PORT})"
echo "  Moonraker 反代: 127.0.0.1:${MR_PORT}"
echo ""

ENABLE="${PLR_NGINX_ENABLE:-}"
if [[ "$ENABLE" == "1" ]]; then
  ln -sf "${OUTD}/plr-backend-fluidd.conf" /etc/nginx/sites-enabled/plr-backend-fluidd.conf
  ln -sf "${OUTD}/plr-backend-mainsail.conf" /etc/nginx/sites-enabled/plr-backend-mainsail.conf
  ln -sf "${OUTD}/plr-gateway-80.conf" /etc/nginx/sites-enabled/plr-gateway-80.conf
  echo "已写入 sites-enabled。若本机已有其它 listen 80 的旧 Fluidd 配置，请先禁用以免冲突。"
  nginx -t
  systemctl reload nginx
  echo "nginx 已 reload。"
else
  echo "未写入 sites-enabled（未设置 PLR_NGINX_ENABLE=1）。启用前请："
  echo "  1) 备份并禁用当前「单站 Fluidd/Mainsail 占 80」的旧配置，避免两个 default_server 冲突；"
  echo "  2) sudo ln -sf ${OUTD}/plr-backend-fluidd.conf /etc/nginx/sites-enabled/"
  echo "     sudo ln -sf ${OUTD}/plr-backend-mainsail.conf /etc/nginx/sites-enabled/"
  echo "     sudo ln -sf ${OUTD}/plr-gateway-80.conf /etc/nginx/sites-enabled/"
  echo "  3) sudo nginx -t && sudo systemctl reload nginx"
  echo ""
  echo "说明见: docs/nginx-generic/README.md"
fi
