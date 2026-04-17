#!/usr/bin/env bash
# 仅从「FlyOS rootfs 源码树」生成可发布的 PLR 目录（供维护者打开发行版）
# 终端用户请勿运行本脚本：请直接使用 GitHub 上已生成的仓库，在标准 Klipper 机器上执行 install/
# 用法: ./build.sh [none|mainsail|fluidd|both]
# 环境变量: FLYOS_ROOT（含 data/klipper 的 rootfs 根）, OUT_DIR, GIT_INIT, GIT_COMMIT
# Bash；Windows 请用 Git Bash / WSL
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLYOS_ROOT="${FLYOS_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/out/klipper-plr-kit}"

# 第一个参数可覆盖 WITH_WEB（none | mainsail | fluidd | both）
if [[ "${1:-}" != "" ]]; then
  WITH_WEB="$1"
else
  WITH_WEB="${WITH_WEB:-none}"
fi
GIT_INIT="${GIT_INIT:-1}"
GIT_COMMIT="${GIT_COMMIT:-0}"

die() { echo "错误: $*" >&2; exit 1; }

case "$WITH_WEB" in
  none|mainsail|fluidd|both) ;;
  *) die "WITH_WEB 须为 none|mainsail|fluidd|both，收到: $WITH_WEB" ;;
esac

DATA="$FLYOS_ROOT/data"
[[ -f "$DATA/klipper/klippy/extras/power_loss_resume.py" ]] || die "检查 FLYOS_ROOT: $FLYOS_ROOT"

rm -rf "$OUT_DIR"
[[ -f "$SCRIPT_DIR/VERSION" ]] && VER="$(tr -d '\r\n' <"$SCRIPT_DIR/VERSION")" || VER="0.0.0"
mkdir -p "$OUT_DIR/klipper/klippy/extras"
mkdir -p "$OUT_DIR/klipperscreen/panels"
mkdir -p "$OUT_DIR/config" "$OUT_DIR/install" "$OUT_DIR/docs"
[[ -f "$SCRIPT_DIR/VERSION" ]] && cp -a "$SCRIPT_DIR/VERSION" "$OUT_DIR/VERSION"

cp -a "$DATA/klipper/klippy/extras/power_loss_resume.py" "$DATA/klipper/klippy/extras/virtual_sdcard.py" \
  "$OUT_DIR/klipper/klippy/extras/"
cp -a "$DATA/KlipperScreen/screen.py" "$OUT_DIR/klipperscreen/"
cp -a "$DATA/KlipperScreen/panels/main_menu.py" "$OUT_DIR/klipperscreen/panels/"

if [[ -f "$FLYOS_ROOT/packaging/plr-one-click/bundle/plr.cfg.example" ]]; then
  cp -a "$FLYOS_ROOT/packaging/plr-one-click/bundle/plr.cfg.example" "$OUT_DIR/config/"
fi
cp -a "$SCRIPT_DIR/install/common.sh" "$SCRIPT_DIR/install/install-klipper.sh" \
  "$SCRIPT_DIR/install/install-klipperscreen.sh" "$SCRIPT_DIR/install/install-web.sh" \
  "$SCRIPT_DIR/install/post-setup.sh" "$SCRIPT_DIR/install/ensure-psutil.sh" \
  "$SCRIPT_DIR/install/diagnose-web-ui.sh" "$OUT_DIR/install/"
cp -a "$SCRIPT_DIR/install.sh" "$OUT_DIR/install.sh"
chmod +x "$OUT_DIR/install.sh" "$OUT_DIR/install/"*.sh

if [[ -f "$SCRIPT_DIR/docs/SKILL.md" ]]; then
  cp -a "$SCRIPT_DIR/docs/SKILL.md" "$OUT_DIR/docs/"
elif [[ -f "$FLYOS_ROOT/docs/skills/flyos-power-loss-resume/SKILL.md" ]]; then
  cp -a "$FLYOS_ROOT/docs/skills/flyos-power-loss-resume/SKILL.md" "$OUT_DIR/docs/"
fi
if [[ -d "$SCRIPT_DIR/docs/nginx-flyos" ]]; then
  mkdir -p "$OUT_DIR/docs/nginx-flyos"
  cp -a "$SCRIPT_DIR/docs/nginx-flyos/." "$OUT_DIR/docs/nginx-flyos/"
fi

GEN="$(date '+%Y-%m-%d %H:%M:%S')"
sed -e "s/{{GENERATED_AT}}/$GEN/g" -e "s/{{VERSION}}/${VER}/g" "$SCRIPT_DIR/README.template.md" > "$OUT_DIR/README.md"
cp -a "$SCRIPT_DIR/.gitignore" "$OUT_DIR/.gitignore"
[[ -f "$SCRIPT_DIR/LICENSE" ]] && cp -a "$SCRIPT_DIR/LICENSE" "$OUT_DIR/LICENSE"
[[ -f "$SCRIPT_DIR/PUBLISH_GITHUB.md" ]] && cp -a "$SCRIPT_DIR/PUBLISH_GITHUB.md" "$OUT_DIR/PUBLISH_GITHUB.md"

if [[ "$WITH_WEB" == "mainsail" || "$WITH_WEB" == "both" ]]; then
  mkdir -p "$OUT_DIR/web"
  if [[ -d "$SCRIPT_DIR/web/mainsail" ]]; then
    cp -a "$SCRIPT_DIR/web/mainsail" "$OUT_DIR/web/"
  else
    cp -a "$DATA/mainsail" "$OUT_DIR/web/"
  fi
fi
if [[ "$WITH_WEB" == "fluidd" || "$WITH_WEB" == "both" ]]; then
  mkdir -p "$OUT_DIR/web"
  if [[ -d "$SCRIPT_DIR/web/fluidd" ]]; then
    cp -a "$SCRIPT_DIR/web/fluidd" "$OUT_DIR/web/"
  else
    cp -a "$DATA/fluidd" "$OUT_DIR/web/"
  fi
fi

echo "完成: $OUT_DIR"

if [[ "$GIT_INIT" == "1" ]] && command -v git >/dev/null; then
  ( cd "$OUT_DIR" && git init && git add . )
  if [[ "$GIT_COMMIT" == "1" ]]; then
    git -C "$OUT_DIR" -c user.email=plr-kit@local -c user.name=plr-kit commit -m "Initial import: FlyOS PLR kit"
  fi
  echo "已 git init（GIT_COMMIT=$GIT_COMMIT）"
fi
