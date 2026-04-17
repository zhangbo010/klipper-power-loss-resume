# `/m/` 打不开 Mainsail — 排障

**推荐**：在常见 Klipper 目录布局下，用 **`sudo bash install/install-nginx-dual-ui.sh`** 生成 **`plr-backend-*`** 与 **`plr-gateway-80.conf`**，见 **`docs/nginx-generic/README.md`**。

## 先确认：你是不是「只有 Moonraker / 单端口」？

很多 **KIAUH / MainsailOS** 环境是：**80 或 81 端口上只有一个网页根**（例如只挂 **Mainsail**），**没有** FlyOS 这种：

- **9080** = Fluidd 整站  
- **9081** = Mainsail 整站  
- **80** = 只负责把 `/m/`、`/f/` **反代**到上面两个端口  

若 **从未** 按 `docs/nginx-flyos/` 里的示例启用 **9080、9081、80 三段配置**，则 **`http://IP/m/#/` 不会存在**，浏览器要么回到首页（Fluidd），要么空白 / 404 —— **这是预期现象**，不是 PLR 安装包能单独修好的。

---

## HTTP **502**（Bad Gateway）

若 **`curl http://127.0.0.1:9081/`** 或 **`http://IP/m/`** 返回 **502**，说明 **nginx 已响应**，但**反向代理到上游失败**（不是「没装静态文件」那么简单）。

### 直连 Moonraker（7125）也出现 502？

若 **`systemctl status moonraker`** 为 **active**，且 **`ss`** 显示 **`0.0.0.0:7125`** 在监听，但 **`curl http://127.0.0.1:7125/server/info`** 仍显示 **502**，请先排除 **HTTP 代理环境变量**：部分环境设置了 **`http_proxy`/`HTTP_PROXY`** 后，**curl 会把 `127.0.0.1` 也交给代理**，代理无法访问你本机 Moonraker，常返回 **502**（易被误判为 Moonraker 故障）。

**请用：**

```bash
curl --noproxy '*' -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:7125/server/info
# 或临时: export NO_PROXY=127.0.0.1,localhost,192.168.0.0/16
```

正常时应为 **200**（或 Moonraker 在特殊状态下为 **5xx**，但不应是「代理假 502」）。

### `ss` 里没有 **9081**

若 **`ss -tlnp | grep 9081`** 为空，说明 **尚未** 部署 **`listen 9081`** 的 Mainsail 站点；此时 **`http://IP/m/`** 也不会按 FlyOS 方式工作。请按 **`docs/nginx-flyos/mainsail.9081.conf`** 增加 **9081**（并修正 **`root`**），再用 **`default.port80.conf`** 在 **80** 上反代 **`/m/`**。

常见原因：

1. **Moonraker 未运行或端口不是 7125**  
   本仓库示例里 **`/api`、`/machine`、`/websocket` 等**会转发到 **`http://127.0.0.1:7125`**。若 Moonraker 停了、或监听在别的地址/端口，这些路径会 **502**。  
   **纯静态首页**在示例 **`mainsail.9081.conf`** 里走 **`location /` + `try_files`**，理论上**不依赖** Moonraker；若你连 **`GET /` 都是 502**，多半是本机 **9081 的 nginx 配置与示例不一致**（例如整站被 `proxy_pass` 到 Moonraker），或存在其它会触发子请求/代理的指令。

2. **`/m/` 反代到 9081，但 9081 本身已 502**  
   此时 **80** 上访问 **`/m/`** 也会是 **502**，与你在诊断里看到的现象一致。

**请执行：**

```bash
# Moonraker 是否在跑、7125 是否通（加 --noproxy 避免 http_proxy 导致假 502）
systemctl status moonraker --no-pager
curl --noproxy '*' -sS -o /dev/null -w "Moonraker HTTP %{http_code}\n" http://127.0.0.1:7125/server/info

# 本机到底是谁在监听 9081、配置是什么
ss -tlnp | grep 9081
sudo nginx -T 2>/dev/null | grep -E 'listen 9081|proxy_pass|root ' | head -40
sudo tail -30 /var/log/nginx/error.log
```

- **`7125` 不通** → 先 **`sudo systemctl start moonraker`**（并检查 `moonraker.conf` 里端口）。  
- **Moonraker 正常、仍 502** → 对照 **`docs/nginx-flyos/mainsail.9081.conf`** 检查 **`root`** 与 **`location /`** 是否为静态 `try_files`，必要时用仓库示例**合并/修正**后 **`nginx -t` && `reload`**。

---

## 快速自检（在打印机 Linux 上执行）

### 1）9081 上有没有 Mainsail？

```bash
ss -tlnp | grep 9081
curl --noproxy '*' -sS -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:9081/
```

- **没有进程监听 9081** → 你还没部署 **`mainsail.9081.conf`** 一类配置，或 nginx 未重载。  
- **`curl` 非 200** → 见上文 **502** 小节；**404** 多为 `root` 错或空目录；**502** 多为 Moonraker/代理问题或配置与示例不一致。

**临时绕过**：若已按文档启了 **9081**，可直接试：

```text
http://192.168.1.192:9081/
```

若 **:9081 正常**、只有 **`/m/` 不正常**，问题在 **80 端口的反代**，不是静态文件本身。

### 2）`root` 路径是否和 `install-web.sh` 一致？

`install-web.sh` 把文件拷到 **探测到的目录**（如 `~/mainsail`），而示例里 **`mainsail.9081.conf`** 常为 **`root /data/mainsail`**。  
两者不一致时，**9081** 会是空站或旧文件。

**处理**：把 **`mainsail.9081.conf`** 里的 **`root`** 改成你**真实**的 Mainsail 目录，或把文件拷到与 `root` 一致的路径，然后：

```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 3）80 上有没有 `/m/` 反代？

```bash
curl --noproxy '*' -sS -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1/m/
grep -R "location.*/m" /etc/nginx/ 2>/dev/null
```

- **404 / 301 到错误页** → **没有** `location /m/` + `proxy_pass ...9081`，或顺序被 **`location /`** 抢走。请用仓库里的 **`default.port80.conf`**，并注意 **`location = /m`** 重定向到 **`/m/`**。

### 4）不要用「仅 Moonraker 静态」冒充 `/m/`

Moonraker **不会**自动提供 **`/m/`** 子路径；若 80 端口是 **Moonraker 内置 HTTP** 或其它单栈，**必须**改成 **nginx/Caddy** 按 FlyOS 方式分流。

---

## 推荐修复顺序

1. 按 **`mainsail.9081.conf`** 启 **9081**，确认 **`http://IP:9081/`** 能打开 Mainsail。  
2. 按 **`fluidd.9080.conf`** 启 **9080**（若要用 Fluidd）。  
3. 用 **`default.port80.conf`** 替换/合并 **80** 站点，**替换 `{{DEFAULT_PORT}}`**，**`nginx -t`** 后 **reload**。  
4. 再访问 **`http://IP/m/`**（建议带尾部 **`/`**），浏览器 **Ctrl+F5**。

---

## 仍失败时

在仓库目录执行（见 `install/diagnose-web-ui.sh`）把终端完整输出保存，便于对照：

```bash
bash install/diagnose-web-ui.sh
```
