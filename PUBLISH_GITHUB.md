# GitHub 发布与使用说明

## A. 终端用户（树莓派等已装标准 Klipper）

**不需要** FlyOS，**不需要**运行 `build.sh`。

1. 在 GitHub 上打开本项目的仓库，**Code → Download ZIP** 或：

   ```bash
   git clone https://github.com/<USER>/<REPO>.git
   cd <REPO>
   ```

2. 按仓库根目录 **`README.md`** 执行：

   ```bash
   sudo apt install python3-psutil   # 或 pip3 install --user psutil
   sudo bash install/install-klipper.sh
   ```

   脚本会自动查找常见路径下的 Klipper（如 `~/klipper`）和 `printer_data`。若失败，请设置 `KLIPPER_HOME`、`PRINTER_DATA` 后再运行。

3. 配置 `plr.cfg`、`printer.cfg` 中的 `[include plr.cfg]`，重启 Klipper。详见 **`docs/SKILL.md`**。

---

## B. 维护者：从 FlyOS 源码树生成发布目录

仅在本地有 **完整 FlyOS rootfs**（含 `data/klipper`、`data/KlipperScreen`）时使用：

```bash
cd packaging/plr-git-kit
chmod +x build.sh
./build.sh
```

生成 **`out/klipper-plr-kit/`**，其内容可作为独立 Git 仓库推送到 GitHub（与终端用户克隆的结构一致）。

可选：`export GIT_COMMIT=1 ./build.sh` 生成首次提交。

---

## C. 在 GitHub 上新建仓库并推送（维护者）

1. https://github.com/new — 新建空仓库（不要勾选自动添加 README）。
2. 本地：

   ```bash
   cd out/klipper-plr-kit
   git status
   git add .
   git commit -m "Initial release: Klipper power loss resume kit"
   git branch -M main
   git remote add origin https://github.com/<USER>/<REPO>.git
   git push -u origin main
   ```

3. **About**：Description 示例：`Power loss resume (PLR) for Klipper — extras + KlipperScreen + optional web UI`  
   **Topics**：`klipper` `moonraker` `mainsail` `fluidd` `klipperscreen` `3d-printing`

4. 若包含 `web/mainsail` 或 `web/fluidd`，仓库会很大，建议主仓只含 Klipper + 脚本 + 文档，大文件用 **Release 附件**。

---

## 许可证

见仓库根目录 **`LICENSE`**（GPLv3）。
