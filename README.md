# PLR Git 打包工具（仅 Bash，维护者用）

**→ 推到 GitHub 新项目**：见根目录 **`GITHUB_NEW_PROJECT.md`**（HTTPS/SSH、`git remote`、`push` 逐步说明）。

---

从 **FlyOS rootfs 源码树**（须含 `data/klipper` 等）抽取文件，生成可推送的目录 **`out/klipper-plr-kit/`**。

**普通用户**：不要运行本脚本。请直接 **git clone** GitHub 上的发行仓库，在已安装**标准 Klipper** 的机器上执行 `install/install-klipper.sh`（见生成包内的 `README.md`）。

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
