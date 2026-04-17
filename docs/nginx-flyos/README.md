# FlyOS 风格：Fluidd / Mainsail 同机切换（`/f/`、`/m/`）

**标准 Klipper 主机（KIAUH 等）**：优先使用 **`docs/nginx-generic/README.md`** 与 **`install/install-nginx-dual-ui.sh`**，按 **`~/mainsail`、`~/fluidd`** 与 Moonraker 端口生成配置；本目录为 FlyOS rootfs **原始片段**对照。

## 原理（与 FlyOS rootfs 一致）

1. **两个独立静态站点**（各用一个端口，根路径即 UI）  
   - **9080**：`root` 指向 Fluidd 目录（如 `/data/fluidd`）  
   - **9081**：`root` 指向 Mainsail 目录（如 `/data/mainsail`）  

2. **80 端口**只做**反向代理**（不直接 `root` 到某一个前端）：  
   - `http://IP/f/`、`/fluidd/` → `http://127.0.0.1:9080/`（路径前缀在代理时剥掉）  
   - `http://IP/m/`、`/mainsail/` → `http://127.0.0.1:9081/`  
   - `http://IP/` → `http://127.0.0.1:9080/` **或** `9081`（由 `flyos-nginx` / `config.txt` 里的 `klipper_webui` 选默认，对应 `{{DEFAULT_PORT}}`）

3. **Moonraker 与摄像头**仍由 **9080/9081** 两个 server 里的 `location` 转发到 `127.0.0.1:7125` 等（与官方 Mainsail/Fluidd 的 nginx 示例相同）。

若只把 **Mainsail 静态文件** 放到 Moonraker 默认目录、**没有** 上述 **9080/9081 + 80 路由**，则访问 **`http://IP/m/#/`** 会**没有**对应 `location`，请求会落到 **`location /`**，看到的仍是**默认 UI**（常为 Fluidd），或出现空白/资源 404。

## 本目录文件

| 文件 | 说明 |
|------|------|
| `default.port80.conf` | **80** 端口：/f、/fluidd、/m、/mainsail 与默认首页（`{{DEFAULT_PORT}}` 替换为 9080 或 9081） |
| `fluidd.9080.conf` | **9080**：Fluidd 静态 + Moonraker/Webcam |
| `mainsail.9081.conf` | **9081**：Mainsail 静态 + Moonraker/Webcam |

部署前请把 `{{DEFAULT_PORT}}` 替换为 **`9080`**（默认 Fluidd）或 **`9081`**（默认 Mainsail）。

## 与 `install-web.sh` 的关系

`install-web.sh` 只负责把本仓库里的 **`web/`** 覆盖到**你本机**的 Mainsail/Fluidd 目录（例如 `~/mainsail`、`~/fluidd`）。  
**不** 负责创建 **9080/9081** 两个 server 和 **80** 路由；若需与 FlyOS 相同的 **`/m/`** 切换，请在本机用 **nginx**（或 Caddy）按上述方式配置，并把 `root` 指到**实际**安装路径（例如 `/data/mainsail` 或 `install-web` 覆盖后的目录）。

## 无斜杠地址

访问 **`http://IP/m`**（无尾部 `/`）时，部分 nginx 不会匹配 `location /m/`，会落到 `location /`，导致错站。`default.port80.conf` 中已增加 **`location = /m`** 等到 `301` 到带斜杠的地址。

## Caddy（FlyOS 可选）

本目录 **`Caddyfile.flyos.example`** 为 FlyOS `etc/caddy/Caddyfile-m` 的精简摘录：`:80` 上 `handle_path /m/*` → `9081`、`/f/*` → `9080`，另设 `:9080`、`:9081` 独立站点；逻辑与 nginx 三端口方案一致。

## 排障

见 **`TROUBLESHOOTING.md`**；仓库 **`install/diagnose-web-ui.sh`** 可在目标机上快速检查 9081 与 `/m/`。
