# 双网页（Mainsail + Fluidd）通用部署说明

本目录说明 **FlyOS 做法背后的原理**，以及如何在 **常见 Klipper 目录布局**（如 KIAUH：`~/mainsail`、`~/fluidd`、`~/printer_data`）下部署**同类能力**，**不绑定** FlyOS 的 `/data/mainsail` 或固定端口习惯。

---

## 1. FlyOS 实际在做什么（抽象成「机制」）

与端口数字无关，核心是三层结构：

| 层级 | 作用 |
|------|------|
| **A. 两个「整站」HTTP 根** | Mainsail、Fluidd 都是单页应用（SPA），各自需要独立 **`root`** + **`try_files … /index.html`**，并各自把 **`/api`、`/websocket`、`/machine`…** 转到 **Moonraker**。 |
| **B. 两个监听端口** | 每个 UI 占一个 **nginx `server { listen … }`**，这样 **Fluidd 始终在「根路径 `/`」**、**Mainsail 也在自己的「根路径 `/`」**，互不抢 `location /`。 |
| **C. 入口端口（常为 80）只做分流** | 用 **`/m/` → 反代到 Mainsail 站**、**`/f/` → 反代到 Fluidd 站**，浏览器地址栏带前缀，静态资源与前端路由才能一致。 |

FlyOS 用 **`/data/mainsail`**、**9080/9081`** 只是其产品化路径与端口选择；**机制**是上面三条。若缺少 **B+C**，只把 Mainsail 文件拷进本机但 **80 上只有 Fluidd 的 `location /**`，则 **`http://IP/m/` 没有对应规则**，会落到默认站——这是行为问题，不是 PLR 包本身能单独「修好」的。

---

## 2. 与「照搬 FlyOS 配置文件」的区别

| FlyOS 示例 | 通用机器上更常见的做法 |
|------------|------------------------|
| `root /data/mainsail` | 使用 **`install-web.sh` / `detect_*` 已支持的路径**：如 **`$HOME/mainsail`**、`$HOME/fluidd`（见 `install/common.sh`） |
| `upstream apiserver` + `conf.d` | 可直接 **`proxy_pass http://127.0.0.1:端口`**，Moonraker 端口从 **`printer_data/config/moonraker.conf`** 的 **`[server]` → `port`** 读取（默认 **7125**） |
| 固定 **9080 / 9081** | 可通过环境变量 **`PLR_FLUIDD_PORT` / `PLR_MAINSAIL_PORT`** 改成未占用端口（默认仍用 9080/9081 以兼容习惯） |

---

## 3. 推荐部署方式（本仓库脚本）

在仓库根目录（克隆后的 `klipper-power-loss-resume`）执行：

```bash
sudo bash install/install-nginx-dual-ui.sh
```

脚本会：

1. 用 **`detect_mainsail_dir` / `detect_fluidd_dir`**（与 `install-web.sh` 同源）解析静态根目录；  
2. 用 **`detect_moonraker_port`** 解析 Moonraker HTTP 端口；  
3. 从 **`install/nginx-templates/`** 生成 **`/etc/nginx/sites-available/plr-*.conf`**；  
4. 执行 **`nginx -t`**；若设置 **`PLR_NGINX_ENABLE=1`** 则建立 **`sites-enabled`** 软链并 **`reload`**。

**环境变量（可选）**

| 变量 | 含义 | 默认 |
|------|------|------|
| `MAINSAIL_DIR` / `FLUIDD_DIR` | 静态根（须含 `index.html`） | 自动探测 |
| `PRINTER_DATA` | 用于找 `config/moonraker.conf` | 自动探测 |
| `PLR_FLUIDD_PORT` | Fluidd 后端 `listen` | `9080` |
| `PLR_MAINSAIL_PORT` | Mainsail 后端 `listen` | `9081` |
| `PLR_DEFAULT_UI` | 80 默认首页指向 `fluidd` 或 `mainsail` | `fluidd` |
| `MOONRAKER_PORT` | 若自动解析失败可手动指定 | `7125` |
| `PLR_NGINX_ENABLE` | 设为 `1` 时启用站点并 reload | 仅生成，不启用 |

**与已有「单站 Fluidd 占 80」并存**：若当前 **`sites-enabled`** 里已有 **`listen 80`** 的 Fluidd，**不要**在未备份的情况下重复启用两个 default server。可选做法：

- **备份**后改用本脚本生成的 **`plr-gateway-80.conf`**（仅反代、无静态 `root`），并**禁用**旧的全站 `fluidd` 配置；或  
- 手工把 **`port80-gateway`** 里的 **`location /m/`、`/f/`** 合并进你现有 **`server { listen 80; ... }`**（进阶，需懂 nginx 优先级）。

---

## 4. Moonraker 与浏览器跨域

若使用 **`http://IP/m/`** 访问 Mainsail，可能需在 **`moonraker.conf`** 的 **`cors_domains`** / **`trusted_clients`** 中允许你的 **`http://IP`** 或带路径的 Origin（以你本机 Moonraker 版本文档为准）。脚本不修改 Moonraker 配置。

---

## 5. 与 `docs/nginx-flyos/` 的关系

- **`docs/nginx-flyos/`**：保留为 **FlyOS 原始片段**对照。  
- **`docs/nginx-generic/` + `install/install-nginx-dual-ui.sh`**：**同一机制**的 **路径/端口可配置** 部署入口，适合标准 Klipper 主机。
