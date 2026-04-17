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

交互安装脚本会在缺少 **`psutil`** 时询问是否用 **apt** 安装。也可先手动安装：

Debian / Ubuntu：

```bash
sudo apt update
sudo apt install -y python3-psutil
```

其他系统：`pip3 install psutil`（需与运行 Klipper 的 Python 一致）。

### 3. 交互安装（推荐）

在**仓库根目录**执行（非 root 时会自动 `sudo` 提权）：

```bash
bash install.sh
```

流程：**检查 psutil** → **确认 Klipper / `printer_data` 路径** → **安装 Klipper 插件** → **可选 KlipperScreen** → **可选部署 Mainsail/Fluidd** → **自动**：`plr.cfg.example` 复制为 `plr.cfg`（若尚无）、在 `printer.cfg` 追加 `[include plr.cfg]`、`systemctl restart klipper`（若本步装了 KlipperScreen 则尝试重启其服务）。**仍需你核对** `plr.cfg` 里的 **`power_pin`** 等与主板一致；浏览器缓存请本地 **Ctrl+F5**（脚本无法代劳）。跳过自动收尾可设环境变量 **`SKIP_AUTO_POST=1`**。

### 4. 仅命令行安装（高级）

不需要交互时，可直接调用子脚本（会按 **`SUDO_USER`** 探测路径；失败时用环境变量）：

```bash
sudo bash install/install-klipper.sh
```

```bash
sudo KLIPPER_HOME=/你的/klipper路径 PRINTER_DATA=/你的/printer_data bash install/install-klipper.sh
```

KlipperScreen（可选）：

```bash
sudo bash install/install-klipperscreen.sh
# 或: sudo KLIPPERSCREEN_HOME=/path/to/KlipperScreen bash install/install-klipperscreen.sh
```

网页端（覆盖本机已安装的 Mainsail/Fluidd 静态目录，**会先备份**为 `目录名.bak.时间戳`）：

```bash
sudo INSTALL_WEB=both bash install/install-web.sh
# 仅其一: INSTALL_WEB=mainsail 或 fluidd
# 自定义路径: sudo MAINSAIL_DIR=/path FLUIDD_DIR=/path INSTALL_WEB=both bash install/install-web.sh
```

### 5. 打印机配置（`install.sh` 已尽量自动完成）

交互安装结束后会运行 **`install/post-setup.sh`**：在 **`printer_data/config/`** 下复制 **`plr.cfg`**、向 **`printer.cfg`** 追加 **`[include plr.cfg]`**、尝试 **`systemctl restart klipper`**（若装了 KlipperScreen 补丁则尝试重启对应服务）。**你必须**打开 **`plr.cfg`** 核对 **`power_pin`** 等硬件相关项。

仅执行了子脚本而未跑完整 **`install.sh`** 时，可手动：

```bash
sudo PRINTER_DATA=/home/你的用户/printer_data bash install/post-setup.sh
# 若本机也装了 KlipperScreen 并希望尝试重启其服务，第二参数传 yes:
sudo bash install/post-setup.sh /home/你的用户/printer_data yes
```

### 6. 网页端说明

本仓库含 **`web/mainsail`**、**`web/fluidd`**。交互安装会询问是否部署；部署后请在浏览器 **Ctrl+F5** 强刷缓存。若使用上游官方前端且未替换，可参考 `docs/SKILL.md`。

### 故障排除：`No module named 'psutil'`

定制版 **`virtual_sdcard.py`** 依赖 **`psutil`**，且必须与 **Klipper 实际使用的 Python** 一致。若只用系统包安装了 **`python3-psutil`**，而 Klipper 运行在 **`~/klipper/venv`** 里，仍会报错。

**处理：**

```bash
# 查看 Klipper 用的 Python（常见为 venv）
grep ExecStart /etc/systemd/system/klipper.service
# 或
ls ~/klipper/venv/bin/python

# 把 psutil 装进该解释器（推荐）
~/klipper/venv/bin/python -m pip install psutil
sudo systemctl restart klipper
```

或在仓库根目录执行（会自动探测 `KLIPPER_HOME`）：

```bash
bash install/ensure-psutil.sh
sudo systemctl restart klipper
```

在网页或控制台执行 **`FIRMWARE_RESTART`** / **`RESTART`** 重新加载。

---

## 仓库目录说明（终端用户）

| 路径 | 说明 |
|------|------|
| `klipper/klippy/extras/` | `power_loss_resume.py`、修改版 `virtual_sdcard.py` |
| `klipperscreen/` | KlipperScreen 相关补丁 |
| `config/` | `plr.cfg.example` |
| `install.sh` | **交互安装入口**（Klipper + 可选 KS + 可选 Web） |
| `install/` | `install-*.sh`、`post-setup.sh`、`ensure-psutil.sh`（psutil 排错） |
| `web/mainsail`、`web/fluidd` | 定制前端静态资源（PLR 弹窗） |

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
