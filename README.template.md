# Klipper 断电续打（PLR）移植包

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](./LICENSE)

Klipper **断电续打（Power Loss Resume）** 整合包：含 Klipper 模块、KlipperScreen 补丁、示例配置、安装脚本与文档。可与 **Moonraker** 及定制 **Mainsail / Fluidd** 前端配合使用。

## 安装方法

### 前提

- 已安装 Klipper（常见：`~/klipper`，含 `klippy/extras`）。
- 使用 Moonraker 时，脚本会尝试探测 `~/printer_data`。

### 1. 获取本仓库

**Git 克隆：**

```bash
git clone https://github.com/zhangbo010/klipper-power-loss-resume.git
cd klipper-power-loss-resume
```

**或** 在 GitHub 页面 **Code → Download ZIP**，解压后进入含 `install/` 的目录。

### 2. 依赖

```bash
sudo apt update
sudo apt install -y python3-psutil
```

其他系统：`pip3 install psutil`（与 Klipper 所用 Python 一致）。

### 3. 安装 Klipper 插件

在仓库根目录：

```bash
sudo bash install/install-klipper.sh
```

脚本按 **`SUDO_USER`** 解析家目录并探测 Klipper / `printer_data`。失败时显式指定：

```bash
sudo KLIPPER_HOME=/你的/klipper路径 PRINTER_DATA=/你的/printer_data bash install/install-klipper.sh
```

### 4. 打印机配置

1. 将 `config/plr.cfg.example` 复制为 `printer_data/config/plr.cfg`（或从已放置的 example 复制改名），按主板修改 **`power_pin`** 等。
2. 在 **`printer.cfg`** 中加入：`[include plr.cfg]`
3. `sudo systemctl restart klipper`

### 5. KlipperScreen（可选）

```bash
sudo bash install/install-klipperscreen.sh
# 或: sudo KLIPPERSCREEN_HOME=/path/to/KlipperScreen bash install/install-klipperscreen.sh
```

### 6. 网页端（Mainsail / Fluidd）

若未含定制 `web/`，需自行部署带 PLR 弹窗的前端（见 `docs/SKILL.md`）。

---

## 本仓库目录说明

| 目录 | 说明 |
|------|------|
| `klipper/klippy/extras/` | `power_loss_resume.py`、修改版 `virtual_sdcard.py` |
| `klipperscreen/` | `screen.py`、`panels/main_menu.py`（PLR 相关改动） |
| `config/` | `plr.cfg.example` |
| `install/` | `install-klipper.sh`、`install-klipperscreen.sh` |
| `docs/` | 功能说明（Skill 摘要） |
| `web/` | （可选）Mainsail/Fluidd，仅部分发行方式包含 |

**Moonraker** 无需补丁。

---

## 开发者：如何从 FlyOS 生成本目录

若你本地有 **FlyOS rootfs** 源码树，可用 `packaging/plr-git-kit/build.sh` 从 `data/` 抽取文件生成与本仓库相同结构的目录（便于发版）。**普通用户只需使用 GitHub 上的本仓库，无需 FlyOS。**

---

## Git / GitHub

```bash
git clone https://github.com/zhangbo010/klipper-power-loss-resume.git
cd klipper-power-loss-resume
# 然后按上文「安装方法」操作
```

维护者首次发布流程见 **`PUBLISH_GITHUB.md`**。

若含 `web/mainsail` 或 `web/fluidd`，体积较大，可考虑 [Git LFS](https://git-lfs.com/) 或 **GitHub Release** 附件。

---

## 许可证

见根目录 **`LICENSE`**（GPLv3）。使用本包须自行承担硬件与配置风险。

---
*生成时间: {{GENERATED_AT}}*
