# Klipper 断电续打（PLR）

## 标准 Klipper 上安装（终端用户）

```bash
git clone https://github.com/zhangbo010/klipper-power-loss-resume.git
cd klipper-power-loss-resume
# Debian/Ubuntu：python3-psutil（install 脚本会检查）
sudo apt install -y python3-psutil
sudo bash install/install-klipper.sh
```

将 **`config/plr.cfg.example`** 拷到打印机配置目录并 **`[include plr.cfg]`**。KlipperScreen 续打入口见 **`install/install-klipperscreen.sh`**。

---

# 维护者：Git 打包工具（仅 Bash）

**→ 推到 GitHub 新项目**：见 **`GITHUB_NEW_PROJECT.md`**。

---

本仓库根目录已包含 **`klipper/`**、**`klipperscreen/`**、**`config/`**，可在**标准 Klipper** 机器上 **`git clone` 后**直接执行 `install/install-klipper.sh`（详见 **`README.template.md`** 生成的说明，或与 GitHub 上 **README** 主文档同步）。

**维护者**：若需从完整 FlyOS `data/` 重新生成发行目录，仍可使用 **`build.sh`** 得到 **`out/klipper-plr-kit/`**。

## 运行环境（仅维护者）

- **Linux / macOS / Git Bash / WSL**
- 当前工作副本须为含 `data/klipper`、`data/KlipperScreen` 的 FlyOS **rootfs** 根目录下的 `packaging/plr-git-kit/`，或通过 **`FLYOS_ROOT`** 指向该 rootfs 根。

## 用法

```bash
cd packaging/plr-git-kit
chmod +x build.sh

# 默认：生成 out/klipper-plr-kit（不含网页），git init + git add
./build.sh

./build.sh mainsail   # 或 fluidd / both（体积大）

export FLYOS_ROOT=/path/to/rootfs   # 可选，默认为本脚本上两级目录
export OUT_DIR=/tmp/my-kit          # 可选，默认 ./out/klipper-plr-kit
export GIT_INIT=0
export GIT_COMMIT=1
```

推送：

```bash
cd out/klipper-plr-kit
git remote add origin <仓库URL>
git push -u origin main
```

详见 **`PUBLISH_GITHUB.md`**。

## 输出物

`README.md`（自 `README.template.md`）、`LICENSE`、`PUBLISH_GITHUB.md`、安装脚本与源码树；**与终端用户在 GitHub 上克隆的仓库内容一致**。
