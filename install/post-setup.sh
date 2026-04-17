#!/usr/bin/env bash
# 安装后自动：plr.cfg、printer.cfg [include]、重启 Klipper（及可选 KlipperScreen）
# 由 install.sh 调用；也可单独:
#   sudo PRINTER_DATA=/path/to/printer_data bash install/post-setup.sh
#   第二参数 yes = 尝试重启 KlipperScreen
# 环境: SUDO_USER（root 下以该用户身份改 config 文件）
set -euo pipefail

PRINTER_DATA="${1:-${PRINTER_DATA:-}}"
RESTART_KS="${2:-no}"

run_as_owner() {
  if [[ -n "${SUDO_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]] && id -u "${SUDO_USER}" &>/dev/null; then
    sudo -u "${SUDO_USER}" -- "$@"
  else
    "$@"
  fi
}

if [[ -z "${PRINTER_DATA}" ]]; then
  echo "post-setup: 未设置 PRINTER_DATA，跳过自动配置。"
  exit 0
fi

CFG="${PRINTER_DATA}/config"
if [[ ! -d "$CFG" ]]; then
  echo "post-setup: 无目录 $CFG，跳过。"
  exit 0
fi

# 1) plr.cfg.example -> plr.cfg（不覆盖已有）
if [[ -f "${CFG}/plr.cfg.example" ]] && [[ ! -f "${CFG}/plr.cfg" ]]; then
  run_as_owner cp -a "${CFG}/plr.cfg.example" "${CFG}/plr.cfg"
  echo "==> 已创建 ${CFG}/plr.cfg"
elif [[ -f "${CFG}/plr.cfg" ]]; then
  echo "==> 已存在 ${CFG}/plr.cfg，未覆盖"
else
  echo "提示: 未找到 ${CFG}/plr.cfg.example，无法自动创建 plr.cfg"
fi

# 2) printer.cfg 追加 [include plr.cfg]
P_CFG="${CFG}/printer.cfg"
if [[ -f "$P_CFG" ]]; then
  if grep -qE '\[include[[:space:]]+plr\.cfg\]' "$P_CFG" 2>/dev/null; then
    echo "==> printer.cfg 已包含 [include plr.cfg]"
  else
    printf '\n# PLR 断电续打（由 klipper-power-loss-resume 安装脚本追加）\n[include plr.cfg]\n' | run_as_owner tee -a "$P_CFG" >/dev/null
    echo "==> 已在 printer.cfg 末尾追加 [include plr.cfg]"
  fi
else
  echo "提示: 未找到 ${P_CFG}，请自行创建主配置并加入 [include plr.cfg]"
fi

echo ""
echo "重要: 请打开 ${CFG}/plr.cfg 按主板核对/修改 power_pin 等项。"

# 3) 重启 Klipper
if command -v systemctl >/dev/null 2>&1; then
  if systemctl restart klipper 2>/dev/null; then
    echo "==> 已执行 systemctl restart klipper"
  else
    echo "提示: systemctl restart klipper 失败（服务名可能不同或无需 systemd），请手动重启 Klipper。"
  fi
else
  echo "提示: 无 systemctl，请手动重启 Klipper。"
fi

# 4) 可选：KlipperScreen
if [[ "${RESTART_KS}" == "yes" ]] || [[ "${RESTART_KS}" == "y" ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    restarted=""
    for u in KlipperScreen klipper-screen; do
      if systemctl cat "${u}.service" &>/dev/null; then
        if systemctl restart "${u}" 2>/dev/null; then
          echo "==> 已执行 systemctl restart ${u}"
          restarted=1
          break
        fi
      fi
    done
    if [[ -z "${restarted}" ]]; then
      echo "提示: 未找到 KlipperScreen systemd 单元，请手动重启触屏服务。"
    fi
  fi
fi

echo ""
echo "网页端：请在浏览器中对控制台页面按 Ctrl+F5 清除缓存（无法由脚本代替）。"
