#!/usr/bin/env bash
# 诊断 /m/、9081、nginx 是否与 FlyOS 三段式一致（在打印机主机上运行）
# bash install/diagnose-web-ui.sh
set -euo pipefail

echo "======== PLR Web UI 诊断（FlyOS 风格：80 + 9080 + 9081）========"
echo ""

echo ">>> [1] 监听端口 80 / 7125(Moonraker) / 9080 / 9081"
if command -v ss >/dev/null 2>&1; then
  ss -tlnp 2>/dev/null | grep -E ':(80|7125|9080|9081)(\s|$)' || true
else
  netstat -tlnp 2>/dev/null | grep -E ':(80|7125|9080|9081)\s' || true
fi
echo ""

echo ">>> [1b] Moonraker 直连（7125 /server/info）"
MR_CODE=""
if MR_CODE=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 3 http://127.0.0.1:7125/server/info 2>/dev/null); then
  echo "    HTTP $MR_CODE"
  if [[ "$MR_CODE" != "200" ]]; then
    echo "    提示: Moonraker 未正常应答时，依赖它的 nginx 反代会 502。"
  fi
else
  echo "    失败: 无法连接 127.0.0.1:7125（Moonraker 未运行或端口不是 7125）"
  MR_CODE="ERR"
fi
echo ""

echo ">>> [2] 本机 Mainsail（9081）根路径 HTTP 状态"
M_CODE=""
if M_CODE=$(curl -sS -o /tmp/plr-diag-m.html -w "%{http_code}" --connect-timeout 3 http://127.0.0.1:9081/ 2>/dev/null); then
  echo "    HTTP $M_CODE"
  if [[ "$M_CODE" == "502" ]]; then
    echo "    502 Bad Gateway: nginx 反代上游失败。常见：Moonraker(7125) 未起、或 9081 的 server 块与"
    echo "    docs/nginx-flyos/mainsail.9081.conf 不一致（例如整站 proxy 到 Moonraker）。"
    echo "    请执行: sudo tail -30 /var/log/nginx/error.log"
    echo "           sudo nginx -T 2>/dev/null | grep -E 'listen 9081|proxy_pass|root ' | head -50"
  elif [[ "$M_CODE" != "200" ]]; then
    echo "    提示: 非 200 时检查 mainsail.9081.conf 的 root 是否与 install-web 部署路径一致。"
  elif head -5 /tmp/plr-diag-m.html 2>/dev/null | grep -qi mainsail; then
    echo "    （响应 HTML 似含 Mainsail）"
  else
    echo "    提示: 状态 200 但内容不像 Mainsail，检查 root 目录是否为 Mainsail 静态文件。"
  fi
else
  echo "    失败: 无服务监听 9081 或拒绝连接 → 尚未配置 nginx :9081 站点。"
  M_CODE="ERR"
fi
echo ""

echo ">>> [3] 本机经 80 访问 /m/"
if curl -sS -o /dev/null -w "    HTTP %{http_code}\n" --connect-timeout 3 http://127.0.0.1/m/ 2>/dev/null; then
  :
else
  echo "    失败: 无法访问 http://127.0.0.1/m/"
fi
echo ""

echo ">>> [4] nginx 配置中与 /m 相关的片段"
if [[ -d /etc/nginx ]]; then
  grep -R "location.*/m" /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | head -20 || echo "    （未找到 location /m）"
else
  echo "    未找到 /etc/nginx"
fi
echo ""

echo ">>> [5] 建议"
if [[ "${MR_CODE:-}" != "200" ]] || [[ "${M_CODE:-}" == "502" ]]; then
  echo "    - 先确认 Moonraker: systemctl status moonraker；curl http://127.0.0.1:7125/server/info 应约返回 200"
fi
echo "    - 若 [2] 为连接失败：部署 docs/nginx-flyos/mainsail.9081.conf 并修正 root，再 reload nginx。"
echo "    - 若 [2] 为 502：按 docs/nginx-flyos/TROUBLESHOOTING.md「HTTP 502」一节排查 error.log 与 nginx -T。"
echo "    - 若 [2] 成功、[3] 失败：部署 docs/nginx-flyos/default.port80.conf，并替换 {{DEFAULT_PORT}}。"
echo "    - 临时可用: http://本机IP:9081/ 直接打开 Mainsail（与 /m/ 等价，仅路径不同）。"
echo ""
rm -f /tmp/plr-diag-m.html 2>/dev/null || true
