# `/m/` 打不开 Mainsail — 排障

## 先确认：你是不是「只有 Moonraker / 单端口」？

很多 **KIAUH / MainsailOS** 环境是：**80 或 81 端口上只有一个网页根**（例如只挂 **Mainsail**），**没有** FlyOS 这种：

- **9080** = Fluidd 整站  
- **9081** = Mainsail 整站  
- **80** = 只负责把 `/m/`、`/f/` **反代**到上面两个端口  

若 **从未** 按 `docs/nginx-flyos/` 里的示例启用 **9080、9081、80 三段配置**，则 **`http://IP/m/#/` 不会存在**，浏览器要么回到首页（Fluidd），要么空白 / 404 —— **这是预期现象**，不是 PLR 安装包能单独修好的。

---

## 快速自检（在打印机 Linux 上执行）

### 1）9081 上有没有 Mainsail？

```bash
ss -tlnp | grep 9081
curl -sS -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:9081/
```

- **没有进程监听 9081** → 你还没部署 **`mainsail.9081.conf`** 一类配置，或 nginx 未重载。  
- **`curl` 非 200** → `root` 目录错、空目录、或权限问题。

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
curl -sS -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1/m/
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
