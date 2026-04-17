# Klipper 断电续打（PLR）移植包

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](./LICENSE)

Klipper **断电续打（Power Loss Resume）** 整合包：含 Klipper 模块、KlipperScreen 补丁、示例配置、安装脚本与文档。可与 **Moonraker** 及定制 **Mainsail / Fluidd** 前端配合使用。

## 在已安装标准 Klipper 的机器上使用（推荐）

适用于通过 **KIAUH**、官方安装脚本或各发行版安装的 Klipper（**不需要** FlyOS 或本仓库外的特殊目录结构）。

1. **克隆或下载本仓库**到打印机主机（例如 `/home/pi/klipper-plr-kit`）。
2. 安装依赖：`sudo apt install python3-psutil` 或 `pip3 install psutil`。
3. 在仓库根目录执行：

```bash
cd /path/to/本仓库
sudo bash install/install-klipper.sh
```

脚本会**自动探测**常见路径下的 Klipper（如 `~/klipper`、`/home/pi/klipper`）和 `printer_data`。若探测失败，可手动指定（注意 `sudo` 会丢弃当前 shell 的环境变量，需写在命令前或使用 `sudo -E`）：

```bash
sudo KLIPPER_HOME=/你的/klipper路径 PRINTER_DATA=/你的/printer_data bash install/install-klipper.sh
```

4. 将 `config/plr.cfg.example` 复制为 `printer_data/config/plr.cfg`（若上一步已复制 example 则编辑之），按主板修改 **`power_pin`** 与续打宏。
5. 在 **`printer.cfg`** 末尾加入：`[include plr.cfg]`
6. `sudo systemctl restart klipper`

**KlipperScreen（可选）**

```bash
sudo bash install/install-klipperscreen.sh
# 或: sudo KLIPPERSCREEN_HOME=/path/to/KlipperScreen bash install/install-klipperscreen.sh
```

**网页端**：若本仓库未含 `web/` 目录，需自行部署带 PLR 弹窗的 Mainsail/Fluidd 静态资源（见 `docs/SKILL.md`）。

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
git clone https://github.com/<USER>/<REPO>.git
cd <REPO>
# 然后按上文「在已安装标准 Klipper 的机器上使用」安装
```

维护者首次发布流程见 **`PUBLISH_GITHUB.md`**。

若含 `web/mainsail` 或 `web/fluidd`，体积较大，可考虑 [Git LFS](https://git-lfs.com/) 或 **GitHub Release** 附件。

---

## 许可证

见根目录 **`LICENSE`**（GPLv3）。使用本包须自行承担硬件与配置风险。

---
*生成时间: {{GENERATED_AT}}*
