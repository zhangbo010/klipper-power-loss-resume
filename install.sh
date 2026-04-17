#!/usr/bin/env bash
# PLR 交互安装：Klipper → 可选 KlipperScreen → 可选 Mainsail/Fluidd 网页
# 用法（在仓库根目录）:
#   bash install.sh
# 若当前非 root，会自动以 sudo 重新执行本脚本。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INST="${ROOT}/install"
# shellcheck source=install/common.sh
source "${INST}/common.sh"

die() { echo "错误: $*" >&2; exit 1; }

# set -e 下 read 遇 EOF/非 TTY 会返回非零导致脚本静默退出，故对交互 read 统一容错
read_yesno() {
  local prompt="$1"
  local _v=""
  if ! IFS= read -r -p "$prompt" _v; then
    echo "" >&2
    echo "（未读取到输入，已按「否」处理。请在真实终端中运行: bash install.sh）" >&2
    _v=""
  fi
  printf '%s' "$_v"
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "将使用 sudo 提权以写入 Klipper / KlipperScreen 目录…"
  exec sudo bash "$0" "$@"
fi

[[ -d "${ROOT}/klipper/klippy/extras" ]] || die "请在克隆后的仓库根目录执行（缺少 klipper/klippy/extras）"

echo ""
echo "======== Klipper 断电续打（PLR）交互安装 ========"
echo "版本: $(plr_kit_version)"
echo ""

# --- Klipper / printer_data 路径 ---
KH=""
PD=""
if KH_TRY="$(detect_klipper_home)"; then
  KH="$KH_TRY"
else
  KH=""
fi
PD="$(detect_printer_data)"

echo "自动探测结果："
echo "  KLIPPER_HOME=${KH:-（未找到）}"
echo "  PRINTER_DATA=${PD:-（未找到）}"
echo ""
echo "  [1] 使用上述路径（若某项未找到，稍后可手动输入）"
echo "  [2] 手动输入 KLIPPER_HOME 与 PRINTER_DATA"
_path_choice="$(read_yesno "请选择 [1/2]（默认 1）: ")"
_path_choice="${_path_choice:-1}"

unset KLIPPER_HOME PRINTER_DATA
case "${_path_choice}" in
  2)
    KLIPPER_HOME="$(read_yesno "KLIPPER_HOME（须含 klippy/extras）: ")"
    PRINTER_DATA="$(read_yesno "PRINTER_DATA（可留空，须含 config/）: ")"
    ;;
  *)
    if [[ -n "$KH" ]]; then
      KLIPPER_HOME="$KH"
    else
      KLIPPER_HOME="$(read_yesno "未探测到 Klipper，请手动输入 KLIPPER_HOME: ")"
    fi
    if [[ -n "$PD" ]]; then
      PRINTER_DATA="$PD"
    else
      PRINTER_DATA="$(read_yesno "未探测到 printer_data，可留空；若需自动放置 plr 示例请输入路径: ")"
    fi
    ;;
esac

[[ -z "${KLIPPER_HOME:-}" ]] && die "必须设置有效的 KLIPPER_HOME"
[[ -d "${KLIPPER_HOME}/klippy/extras" ]] || die "无效的 KLIPPER_HOME: $KLIPPER_HOME"

export KLIPPER_HOME
if [[ -n "${PRINTER_DATA:-}" ]]; then
  export PRINTER_DATA
else
  unset PRINTER_DATA
fi

# --- psutil：必须与 Klipper 实际使用的 Python 一致（KIAUH 常见为 ~/klipper/venv；仓库 vendor/psutil 可离线安装）---
KPY="$(detect_klipper_python)" || die "无法找到 python3，请先安装 Python3。"
echo "==> Klipper 使用的 Python（用于检查 psutil）: $KPY"
if [[ "${SKIP_ENSURE_PSUTIL:-}" == "1" ]]; then
  echo "已设置 SKIP_ENSURE_PSUTIL=1，跳过 ensure-psutil（请自行保证 psutil 已装入该 Python）。"
else
  if ! "$KPY" -c "import psutil" 2>/dev/null; then
    echo "==> 未检测到 psutil，自动执行 install/ensure-psutil.sh（优先 vendor/psutil 离线 wheel）…"
    bash "${INST}/ensure-psutil.sh" || die "psutil 安装失败，请见 README"
  fi
  "$KPY" -c "import psutil" 2>/dev/null || die "psutil 仍不可用，请执行: bash install/ensure-psutil.sh"
fi

echo ""
echo ">>> 正在安装 Klipper 插件 …"
# 以实际登录用户执行复制，避免 sudo 下 root 无法读取 NFS home（root_squash）导致静默失败
if [[ -n "${SUDO_USER:-}" ]]; then
  sudo -u "${SUDO_USER}" env KLIPPER_HOME="${KLIPPER_HOME}" PRINTER_DATA="${PRINTER_DATA:-}" bash "${INST}/install-klipper.sh"
else
  bash "${INST}/install-klipper.sh"
fi

echo ""
echo ">>> Klipper 插件已写入。接下来为可选步骤（KlipperScreen / 网页端）。"
echo ""

# --- 可选 KlipperScreen ---
DID_KS=no
_ks="$(read_yesno "是否安装 KlipperScreen 补丁（续打入口）？[y/N] ")"
if [[ "${_ks}" == [yY]* ]]; then
  DID_KS=yes
  unset KLIPPERSCREEN_HOME
  KS=""
  if KS_TRY="$(detect_klipperscreen_home)"; then
    KS="$KS_TRY"
  fi
  echo "探测到 KlipperScreen: ${KS:-（未找到）}"
  _ksc="$(read_yesno "使用该路径？[Y/n/手动输入 m] ")"
  _ksc="${_ksc:-Y}"
  case "${_ksc}" in
    [Mm]*)
      KLIPPERSCREEN_HOME="$(read_yesno "KLIPPERSCREEN_HOME: ")"
      export KLIPPERSCREEN_HOME
      ;;
    [Nn]*)
      KLIPPERSCREEN_HOME="$(read_yesno "KLIPPERSCREEN_HOME: ")"
      export KLIPPERSCREEN_HOME
      ;;
    *)
      if [[ -n "$KS" ]]; then
        export KLIPPERSCREEN_HOME="$KS"
      else
        KLIPPERSCREEN_HOME="$(read_yesno "请手动输入 KLIPPERSCREEN_HOME: ")"
        export KLIPPERSCREEN_HOME
      fi
      ;;
  esac
  [[ -n "${KLIPPERSCREEN_HOME:-}" ]] || die "未设置 KLIPPERSCREEN_HOME"
  [[ -f "${KLIPPERSCREEN_HOME}/screen.py" ]] || die "无效的 KLIPPERSCREEN_HOME: $KLIPPERSCREEN_HOME"
  echo ""
  echo ">>> 正在安装 KlipperScreen 补丁 …"
  if [[ -n "${SUDO_USER:-}" ]]; then
    sudo -u "${SUDO_USER}" env KLIPPERSCREEN_HOME="${KLIPPERSCREEN_HOME}" bash "${INST}/install-klipperscreen.sh"
  else
    bash "${INST}/install-klipperscreen.sh"
  fi
fi

# --- 可选：Mainsail / Fluidd（定制 PLR 弹窗）---
WEB_MS="${ROOT}/web/mainsail/index.html"
WEB_FD="${ROOT}/web/fluidd/index.html"
_web=""
WEB_BOTH_OK=0
if [[ -f "$WEB_MS" ]] || [[ -f "$WEB_FD" ]]; then
  echo ""
  echo "网页端：本仓库含定制 Mainsail/Fluidd 静态资源（续打弹窗）。"
  echo "  [y] 两者都部署  [m] 仅 Mainsail  [f] 仅 Fluidd  [n] 跳过"
  _web="$(read_yesno "是否部署到本机 Moonraker 网页目录？[y/m/f/N] ")"
  _web="${_web:-n}"
  if [[ "${_web}" == [yY]* ]]; then
    export INSTALL_WEB=both
    if bash "${INST}/install-web.sh"; then
      WEB_BOTH_OK=1
    else
      echo "提示: 若仅安装其一或路径特殊，可稍后执行: sudo INSTALL_WEB=mainsail|fluidd MAINSAIL_DIR=... FLUIDD_DIR=... bash install/install-web.sh"
    fi
  elif [[ "${_web}" == [mM]* ]] && [[ -f "$WEB_MS" ]]; then
    export INSTALL_WEB=mainsail
    bash "${INST}/install-web.sh" || true
  elif [[ "${_web}" == [fF]* ]] && [[ -f "$WEB_FD" ]]; then
    export INSTALL_WEB=fluidd
    bash "${INST}/install-web.sh" || true
  fi
else
  echo ""
  echo "（未找到 web/mainsail 或 web/fluidd，已跳过网页部署。完整克隆仓库后重试。）"
fi

# 两者都部署成功且仓库含双端静态文件时：生成 plr nginx 配置、移出冲突旧站点、写入 sites-enabled 并 reload
if [[ "${SKIP_NGINX_DUAL_UI:-}" != "1" ]] && [[ -f "${ROOT}/install/install-nginx-dual-ui.sh" ]]; then
  if [[ "${_web}" == [yY]* ]] && [[ "$WEB_BOTH_OK" == "1" ]] && [[ -f "$WEB_MS" && -f "$WEB_FD" ]]; then
    echo ""
    echo ">>> 生成并启用 nginx 双 UI（http://IP/m/ 与 /f/），并处理旧站点冲突…"
    if PLR_NGINX_ENABLE=1 bash "${INST}/install-nginx-dual-ui.sh"; then
      :
    else
      echo "提示: 可稍后手动执行: sudo PLR_NGINX_ENABLE=1 bash install/install-nginx-dual-ui.sh（见 docs/nginx-generic/README.md）"
    fi
  fi
fi

echo ""
echo "======== 自动完成配置与重启 ========"
if [[ "${SKIP_AUTO_POST:-}" == "1" ]]; then
  echo "已设置 SKIP_AUTO_POST=1，跳过 post-setup（plr.cfg / printer.cfg / systemctl）。"
else
  bash "${INST}/post-setup.sh" "${PRINTER_DATA:-}" "${DID_KS}"
fi

echo ""
echo "======== 安装步骤已完成 ========"
echo "请务必检查 ${PRINTER_DATA:-printer_data}/config/plr.cfg 中的 power_pin 等与主板一致。"
echo ""
