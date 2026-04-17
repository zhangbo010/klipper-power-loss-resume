#!/usr/bin/env bash
# 诊断 /m/、9081、nginx 是否与 FlyOS 三段式一致（在打印机主机上运行）
# bash install/diagnose-web-ui.sh
set -euo pipefail

echo "======== PLR Web UI 诊断（FlyOS 风格：80 + 9080 + 9081）========"
echo ""

echo ">>> [1] 监听端口 80 / 9080 / 9081"
if command -v ss >/dev/null 2>&1; then
  ss -tlnp 2>/dev/null | grep -E ':(80|9080|9081)(\s|$)' || true
else
  netstat -tlnp 2>/dev/null | grep -E ':(80|9080|9081)\s' || true
fi
echo ""

echo ">>> [2] 本机 Mainsail（9081）根路径 HTTP 状态"
if curl -sS -o /tmp/plr-diag-m.html -w "HTTP %{http_code}\n" --connect-timeout 3 http://127.0.0.1:9081/ 2>/dev/null; then
  if head -5 /tmp/plr-diag-m.html 2>/dev/null | grep -qi mainsail; then
    echo "    （响应 HTML 似含 Mainsail）"
  else
    echo "    提示: 若状态非 200 或内容不像 Mainsail，请检查 mainsail.9081.conf 的 root 是否与 install-web 部署路径一致。"
  fi
else
  echo "    失败: 无服务监听 9081 或拒绝连接 → 尚未配置 nginx :9081 站点。"
fi
echo ""

echo ">>> [3] 本机经 80 访问 /m/（仅当 nginx 监听 127.0.0.1:80 时有效）"
curl -sS -o /dev/null -w "HTTP %{http_code}\n" --connect-timeout 3 http://127.0.0.1/m/ 2>/dev/null || echo "    失败: 无法访问 http://127.0.0.1/m/"
echo ""

echo ">>> [4] nginx 配置中与 /m 相关的片段"
if [[ -d /etc/nginx ]]; then
  grep -R "location.*/m" /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | head -20 || echo "    （未找到 location /m）"
else
  echo "    未找到 /etc/nginx"
fi
echo ""

echo ">>> [5] 建议"
echo "    - 若 [2] 失败：先部署 docs/nginx-flyos/mainsail.9081.conf 并修正 root，再 reload nginx。"
echo "    - 若 [2] 成功、[3] 失败：部署 docs/nginx-flyos/default.port80.conf，并替换 {{DEFAULT_PORT}}。"
echo "    - 临时可用: http://本机IP:9081/ 直接打开 Mainsail（与 /m/ 等价，仅路径不同）。"
echo ""
rm -f /tmp/plr-diag-m.html 2>/dev/null || true
