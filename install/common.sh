#!/usr/bin/env bash
# 供 install-*.sh 与交互安装脚本 source；勿单独执行
# shellcheck shell=bash

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

# Klipper 实际使用的 Python（KIAUH 等常为 ~/klipper/venv/bin/python，与系统 python3 不同）
detect_klipper_python() {
  local kh="${KLIPPER_HOME:-}"
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
