#!/usr/bin/env bash
# 由 install-nginx-dual-ui.sh source；勿单独执行
# 在启用 plr-* 站点前，将 sites-enabled 下占用 PLR 所用端口的其它站点移出（软链备份）
# shellcheck shell=bash

# 解析 nginx 配置中 listen 行是否使用端口集合中的任一端（避免 8080 误匹配 80）
plr_nginx_conf_listens_on_ports() {
  local f="$1"
  local p80="${2:-80}" pf="${3:-9080}" pm="${4:-9081}"
  [[ -f "$f" ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -c '
import re, sys
path = sys.argv[1]
ports = {int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])}
with open(path) as fp:
    for line in fp:
        line = line.split("#")[0].strip()
        if not line or not re.match(r"\s*listen\s", line):
            continue
        for m in re.finditer(r"(?:^|\s)(?:\[[0-9a-fA-F:.]+\]|[0-9.]+):(\d+)\b", line):
            if int(m.group(1)) in ports:
                sys.exit(0)
        m = re.match(r"^\s*listen\s+(\d+)\s*;", line)
        if m and int(m.group(1)) in ports:
            sys.exit(0)
sys.exit(1)
' "$f" "$p80" "$pf" "$pm" 2>/dev/null
}

plr_disable_conflicting_nginx_sites() {
  local se_dir="/etc/nginx/sites-enabled"
  [[ -d "$se_dir" ]] || {
    echo "提示: 无 ${se_dir}，跳过冲突站点处理。"
    return 0
  }

  if [[ "${PLR_SKIP_DISABLE_CONFLICTING:-}" == "1" ]]; then
    echo "已跳过禁用冲突站点（PLR_SKIP_DISABLE_CONFLICTING=1）。"
    return 0
  fi

  local backup_dir
  backup_dir="${se_dir}/.plr-disabled-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$backup_dir"

  local p80="${PLR_HTTP_PORT:-80}"
  local pf="${PLR_FLUIDD_PORT:-9080}"
  local pm="${PLR_MAINSAIL_PORT:-9081}"

  local moved=0
  local path base target conflict

  for path in "$se_dir"/*; do
    [[ -e "$path" ]] || continue
    base="$(basename "$path")"
    [[ -d "$path" ]] && continue
    [[ "$base" == .plr-disabled-* ]] && continue
    [[ "$base" == plr-* ]] && continue

    if [[ -L "$path" ]]; then
      target="$(readlink -f "$path" 2>/dev/null || true)"
    else
      target="$path"
    fi
    [[ -n "$target" && -f "$target" ]] || continue

    conflict=0
    if command -v python3 >/dev/null 2>&1; then
      if plr_nginx_conf_listens_on_ports "$target" "$p80" "$pf" "$pm"; then
        conflict=1
      fi
    else
      case "$base" in
        default|fluidd|mainsail) conflict=1 ;;
      esac
    fi

    if [[ "$conflict" == "1" ]]; then
      echo "==> 暂时移出占用端口 ${p80}/${pf}/${pm} 的站点: ${path} -> ${backup_dir}/"
      mv "$path" "${backup_dir}/"
      moved=$((moved + 1))
    fi
  done

  if [[ "$moved" -gt 0 ]]; then
    echo "==> 已备份 ${moved} 个站点至 ${backup_dir}，恢复时可移回 ${se_dir}/"
  else
    rmdir "$backup_dir" 2>/dev/null || true
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "提示: 未找到 python3，仅按站点名 default|fluidd|mainsail 做了保守处理；建议安装 python3 后重跑以按 listen 精确检测。"
  fi
}
