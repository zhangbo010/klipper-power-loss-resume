# Klipper 断电续打（PLR）

适用于已通过 **KIAUH**、官方脚本或各发行版安装的 **标准 Klipper**（**不需要** FlyOS）。可与 **Moonraker** 及定制 **Mainsail / Fluidd** 前端配合；详见 `docs/SKILL.md`。

## 安装方法

### 前提

- 打印机主机上已安装 Klipper（常见目录：`~/klipper`，含 `klippy/extras`）。
- 建议使用 Moonraker 时的默认 `printer_data/config`（脚本会尝试自动探测）。

### 1. 获取本仓库

**方式 A：Git 克隆（推荐）**

```bash
git clone https://github.com/zhangbo010/klipper-power-loss-resume.git
cd klipper-power-loss-resume
```

**方式 B：ZIP 下载**

在 [GitHub 仓库页](https://github.com/zhangbo010/klipper-power-loss-resume) 选择 **Code → Download ZIP**，解压后 `cd` 到解压出的目录（须能看到 `install/`、`klipper/`）。

### 2. 依赖

Debian / Ubuntu：

```bash
sudo apt update
sudo apt install -y python3-psutil
```

其他系统可用：`pip3 install psutil`（需与运行 Klipper 的 Python 一致）。

### 3. 安装 Klipper 插件

在**仓库根目录**（包含 `install/install-klipper.sh`）执行：

```bash
sudo bash install/install-klipper.sh
```

脚本会按 **`SUDO_USER`** 解析真实用户家目录，并尝试探测 `~/klipper`、`~/printer_data` 等。若探测失败，可显式指定（注意 `sudo` 会丢弃当前 shell 的环境变量，请写在命令前）：

```bash
sudo KLIPPER_HOME=/你的/klipper路径 PRINTER_DATA=/你的/printer_data bash install/install-klipper.sh
```

### 4. 打印机配置

1. 将 `config/plr.cfg.example` 复制为 `printer_data/config/plr.cfg`（若安装脚本已写入 `plr.cfg.example`，可复制并改名）。
2. 按主板修改 **`power_pin`** 及续打相关宏。
3. 在 **`printer.cfg`** 中加入：`[include plr.cfg]`
4. 重启 Klipper：

```bash
sudo systemctl restart klipper
```

### 5. KlipperScreen（可选）

若使用 KlipperScreen，在仓库根目录执行：

```bash
sudo bash install/install-klipperscreen.sh
# 或: sudo KLIPPERSCREEN_HOME=/path/to/KlipperScreen bash install/install-klipperscreen.sh
```

然后重启 KlipperScreen 服务（如 `sudo systemctl restart KlipperScreen`，具体以你系统为准）。

### 6. 网页端（Mainsail / Fluidd）

若仓库中未包含定制 `web/` 静态资源，需自行部署带 PLR 弹窗的 Mainsail/Fluidd（见 `docs/SKILL.md`）。

---

## 仓库目录说明（终端用户）

| 路径 | 说明 |
|------|------|
| `klipper/klippy/extras/` | `power_loss_resume.py`、修改版 `virtual_sdcard.py` |
| `klipperscreen/` | KlipperScreen 相关补丁 |
| `config/` | `plr.cfg.example` |
| `install/` | `install-klipper.sh`、`install-klipperscreen.sh` |

**Moonraker** 无需补丁。

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
