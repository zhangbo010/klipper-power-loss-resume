# Klipper 断电续打（PLR）移植包

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](./LICENSE)
![Version](https://img.shields.io/badge/version-{{VERSION}}-informational)

**版本：{{VERSION}}**（由 `build.sh` 自 `VERSION` 注入；根目录 `VERSION` 为唯一源。）

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

**psutil**：定制 **`virtual_sdcard`** 需要；须与 **`klipper.service` 里实际运行的 Python** 一致（脚本会从 **`ExecStart`** 解析；FlyOS 等常为 **`/usr/bin/python`** 而非 venv）。仓库含 **`vendor/psutil/*.whl`**（Linux x86_64 / aarch64），**`install/ensure-psutil.sh`** 优先离线安装。若仍报 **`No module named 'psutil'`**，可设 **`KLIPPER_PYTHON`** 与 **`systemctl cat klipper.service`** 中解释器路径一致后再执行 **`bash install/ensure-psutil.sh`**。

### 3. 交互安装（推荐）

在仓库根目录（非 root 时会自动 `sudo`）：

```bash
bash install.sh
# 或: chmod +x install.sh && ./install.sh
```

若 **`Permission denied`**：`chmod +x install.sh` 后再 `./install.sh`，或只用 **`bash install.sh`**（`install` 为目录，勿当脚本执行）。

流程：**自动 ensure-psutil**（缺则装，优先 **vendor/psutil**）→ 确认路径 → 安装 Klipper → 可选 **KlipperScreen** → 可选 **Mainsail/Fluidd** → **自动** `plr.cfg`、`printer.cfg` include、`systemctl restart klipper`（及 KS）。须核对 **`power_pin`**；浏览器 **Ctrl+F5** 需自行操作。跳过收尾：`SKIP_AUTO_POST=1`。

### 4. 仅命令行安装（高级）

```bash
sudo bash install/install-klipper.sh
sudo KLIPPER_HOME=/你的/klipper路径 PRINTER_DATA=/你的/printer_data bash install/install-klipper.sh
sudo bash install/install-klipperscreen.sh
sudo INSTALL_WEB=both bash install/install-web.sh
sudo PRINTER_DATA=/path/to/printer_data bash install/post-setup.sh
```

交互 **`install.sh`**：选 **同时部署** Mainsail+Fluidd 且成功后，会自动 **`PLR_NGINX_ENABLE=1`** 执行 **`install-nginx-dual-ui.sh`**（生成、移出冲突旧站点、启用并 reload）；跳过可加 **`SKIP_NGINX_DUAL_UI=1`**。

### 5. 打印机配置

`install.sh` 会调用 **`install/post-setup.sh`** 自动复制 **`plr.cfg`**、追加 **`[include plr.cfg]`**、重启服务；**仍须编辑 `plr.cfg` 中 `power_pin`**。仅子脚本安装时请自行执行上一段中的 **`post-setup.sh`**。

### 6. 网页端

本仓库含 **`web/mainsail`**、**`web/fluidd`**（来自 git，**不**拉取官方 zip）。若本机尚无前端，**`install-web.sh`** 会装到默认 **`~/mainsail`、`~/fluidd`**。交互 **`install.sh`** 会询问是否部署；**`/m/`、`/f/` 同机切换**见 **`docs/nginx-generic/README.md`**，并执行 **`sudo bash install/install-nginx-dual-ui.sh`**。FlyOS 片段对照见 **`docs/nginx-flyos/`**。部署后强刷浏览器缓存。若 **`/m/` 打不开**，见 **`docs/nginx-flyos/TROUBLESHOOTING.md`**，或运行 **`bash install/diagnose-web-ui.sh`**；已启用 Mainsail 后端端口时可先试 **`http://IP:9081/`**（若改过 **`PLR_MAINSAIL_PORT`** 则用对应端口）。

---

## 本仓库目录说明

| 目录 | 说明 |
|------|------|
| `klipper/klippy/extras/` | `power_loss_resume.py`、修改版 `virtual_sdcard.py` |
| `klipperscreen/` | `screen.py`、`panels/main_menu.py`（PLR 相关改动） |
| `config/` | `plr.cfg.example` |
| `install.sh` | **交互安装入口**（Klipper + 可选 KS + Web） |
| `install/` | `common.sh`、`install-*.sh`、`post-setup.sh`、`ensure-psutil.sh`、`download-vendor-psutil.sh`、`diagnose-web-ui.sh`、`install-nginx-dual-ui.sh`、`nginx-disable-conflicting-sites.sh`、`nginx-templates/` |
| `vendor/psutil/` | 随仓库提供的 psutil 离线 wheel |
| `docs/` | 功能说明；**`nginx-generic/`** 双 UI 通用部署；**`nginx-flyos/`** FlyOS 片段对照 |
| `web/mainsail`、`web/fluidd` | 定制前端静态资源 |

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
*版本 {{VERSION}} · 生成时间: {{GENERATED_AT}}*
