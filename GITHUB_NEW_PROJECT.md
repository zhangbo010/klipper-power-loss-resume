# 把本功能推到 GitHub 新项目

## 方案 A：推送「工具仓库」（推荐先完成，已有本地 Git）

本目录 **`packaging/plr-git-kit`** 已是独立 Git 仓库，含 **安装脚本、文档、build.sh、LICENSE**，可直接作为 GitHub 上的**主项目**。

### 1. 在 GitHub 新建空仓库

1. 打开 https://github.com/new  
2. **Repository name**：例如 `klipper-power-loss-resume`  
3. **不要**勾选 README / .gitignore / License（本地已有）  
4. 创建后复制 **HTTPS** 地址，例如：  
   `https://github.com/<你的用户名>/<仓库名>.git`

### 2. 在本机推送（PowerShell）

```powershell
cd "e:\souce code\FlyOS_extracted\rootfs\packaging\plr-git-kit"

git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git branch -M main
git push -u origin main
```

若提示 `remote origin already exists`：

```powershell
git remote set-url origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

若使用 **SSH**：

```powershell
git remote add origin git@github.com:<你的用户名>/<仓库名>.git
git push -u origin main
```

### 3. 登录与权限

- **HTTPS**：GitHub 已不支持账户密码推送，需使用 **Personal Access Token**（Settings → Developer settings → Personal access tokens）作为密码。  
- **SSH**：在 GitHub 上添加本机 **SSH 公钥**（Settings → SSH keys）。

---

## 方案 B：只发布「给终端用户用的发行包」（不含 build.sh）

若希望 GitHub 上**只有** `klipper/`、`klipperscreen/`、`install/`、`config/` 等（不含 FlyOS 打包脚本），在 **Linux / 本机 Git Bash** 或 **WSL 正常** 时执行：

```bash
cd packaging/plr-git-kit
chmod +x build.sh
export GIT_INIT=0
./build.sh
cd out/klipper-plr-kit
git init
git add .
git commit -m "Initial release: Klipper PLR files"
git branch -M main
git remote add origin https://github.com/<USER>/<REPO>-dist.git
git push -u origin main
```

再新建一个 **空仓库**（例如 `klipper-plr-dist`）推送上述内容。

---

## 推送后建议

- 在仓库 **About** 里填写 Description，并添加 Topics：`klipper` `moonraker` `mainsail` `fluidd` `3d-printing`

---

## 后续更新 `docs/SKILL.md`

若你在 **`docs/skills/flyos-power-loss-resume/SKILL.md`** 里改了文档，可同步到本仓库再推送：

```powershell
Copy-Item "..\..\docs\skills\flyos-power-loss-resume\SKILL.md" "docs\SKILL.md" -Force
cd "e:\souce code\FlyOS_extracted\rootfs\packaging\plr-git-kit"
git add docs/SKILL.md
git commit -m "docs: sync SKILL"
git push
```

（路径请按你本机 `rootfs` 实际位置调整。）
