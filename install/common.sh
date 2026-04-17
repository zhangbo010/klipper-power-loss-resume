#!/usr/bin/env bash
# 供 install-*.sh 与交互安装脚本 source；勿单独执行
# shellcheck shell=bash

# 仓库根目录单行 VERSION 文件（与 README 发版号同步）
plr_kit_version() {
  local root vf
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  vf="${root}/VERSION"
  if [[ -f "$vf" ]]; then
    tr -d '\r\n' <"$vf"
  else
    echo "unknown"
  fi
}

# sudo 时 HOME 常为 /root，改用实际登录用户的家目录
effective_home() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    getent passwd "$SUDO_USER" | cut -d: -f6
  else
    echo "$HOME"
  fi
}

# 自动探测 KLIPPER_HOME（标准安装常见路径）
detect_klipper_home() {
  local d EH
  EH="$(effective_home)"
  for d in \
    "${KLIPPER_HOME:-}" \
    "${EH}/klipper" \
    "${EH}/Klipper" \
    /data/klipper \
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
  local d EH
  EH="$(effective_home)"
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

# 自动探测 KlipperScreen 安装目录
detect_klipperscreen_home() {
  local d EH
  EH="$(effective_home)"
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

# 从 systemd 单元解析 Klipper 实际使用的 Python（须与 klippy 进程一致，否则 psutil 会装错环境）
# FlyOS 等常为 ExecStart=/usr/bin/python /data/klipper/klippy/klippy.py ...（无 venv，且可能不同于 `python3`）
detect_klipper_python_from_systemd() {
  local candidates line exec_line first
  candidates=""
  if command -v systemctl >/dev/null 2>&1; then
    candidates="$(systemctl cat klipper.service 2>/dev/null || true)"
  fi
  if [[ -z "$candidates" ]] && [[ -f /etc/systemd/system/klipper.service ]]; then
    candidates="$(cat /etc/systemd/system/klipper.service)"
  fi
  if [[ -z "$candidates" ]] && [[ -f /lib/systemd/system/klipper.service ]]; then
    candidates="$(cat /lib/systemd/system/klipper.service)"
  fi
  line="$(echo "$candidates" | grep '^ExecStart=' | head -1)" || return 1
  [[ -z "$line" ]] && return 1
  exec_line="${line#ExecStart=}"
  exec_line="$(echo "$exec_line" | sed 's/^[[:space:]]*//')"
  # systemd 允许 ExecStart 第一个参数前加 - : @ + !（忽略失败、特权等）
  while [[ "$exec_line" =~ ^[-+:@!] ]]; do
    exec_line="${exec_line:1}"
    exec_line="$(echo "$exec_line" | sed 's/^[[:space:]]*//')"
  done
  read -r first _ <<< "$exec_line"
  [[ -z "$first" ]] && return 1
  case "$(basename "$first")" in
    python|python2|python3|python2.*|python3.*) ;;
    *) return 1 ;;
  esac
  [[ -x "$first" ]] || return 1
  echo "$first"
  return 0
}

# Klipper 实际使用的 Python（KIAUH 等常为 ~/klipper/venv/bin/python，与系统 python3 不同）
# 顺序：显式 KLIPPER_PYTHON → systemd ExecStart（与运行中服务一致）→ venv → PATH 中的 python3
detect_klipper_python() {
  local kh="${KLIPPER_HOME:-}" py
  if [[ -n "${KLIPPER_PYTHON:-}" ]] && [[ -x "${KLIPPER_PYTHON}" ]]; then
    echo "${KLIPPER_PYTHON}"
    return 0
  fi
  if py="$(detect_klipper_python_from_systemd)"; then
    echo "$py"
    return 0
  fi
  if [[ -n "$kh" ]]; then
    if [[ -x "${kh}/venv/bin/python" ]]; then
      echo "${kh}/venv/bin/python"
      return 0
    fi
    if [[ -x "${kh}/.venv/bin/python" ]]; then
      echo "${kh}/.venv/bin/python"
      return 0
    fi
  fi
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi
  return 1
}

# 无现成安装时，将本仓库 web/* 解压/复制到的默认路径（与 KIAUH 常见布局一致）
default_mainsail_install_dir() {
  echo "$(effective_home)/mainsail"
}

default_fluidd_install_dir() {
  echo "$(effective_home)/fluidd"
}

# 探测 Mainsail 静态根目录（须含 index.html）
detect_mainsail_dir() {
  local d EH
  EH="$(effective_home)"
  for d in \
    "${MAINSAIL_DIR:-}" \
    "${EH}/mainsail" \
    /home/pi/mainsail \
    /usr/data/mainsail \
    /var/www/mainsail; do
    [[ -z "$d" ]] && continue
    if [[ -f "$d/index.html" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

# 从 printer_data 下 moonraker.conf 的 [server] 段读取 port（默认 7125）
detect_moonraker_port() {
  local pd cf port
  pd="${PRINTER_DATA:-}"
  [[ -z "$pd" ]] && pd="$(detect_printer_data || true)"
  [[ -z "$pd" ]] && return 1
  cf="${pd}/config/moonraker.conf"
  [[ -f "$cf" ]] || return 1
  port="$(awk '
    /^\[server\]/ { s=1; next }
    /^\[/ { s=0; next }
    s && /^[[:space:]]*port:[[:space:]]*[0-9]+/ {
      match($0, /[0-9]+/)
      print substr($0, RSTART, RLENGTH)
      exit
    }
  ' "$cf")"
  [[ -n "$port" ]] || return 1
  echo "$port"
  return 0
}

# 探测 Fluidd 静态根目录（须含 index.html）
detect_fluidd_dir() {
  local d EH
  EH="$(effective_home)"
  for d in \
    "${FLUIDD_DIR:-}" \
    "${EH}/fluidd" \
    /home/pi/fluidd \
    /usr/data/fluidd \
    /var/www/fluidd; do
    [[ -z "$d" ]] && continue
    if [[ -f "$d/index.html" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}
