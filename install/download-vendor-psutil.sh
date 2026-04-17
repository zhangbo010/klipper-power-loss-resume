#!/usr/bin/env bash
# 维护者：下载 Linux 常用架构 psutil wheel 到 vendor/psutil（发版或更新依赖时执行）
# 需联网；在任意装有 pip 的机器上运行即可
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(cd "${SCRIPT_DIR}/.." && pwd)/vendor/psutil"
mkdir -p "$OUT"
echo "==> 输出目录: $OUT"
# cp36-abi3 / cp37-abi3 wheel 可被 Python 3.6+ 使用
for args in \
  "--platform manylinux2014_aarch64 --python-version 311" \
  "--platform manylinux2010_x86_64 --python-version 311" \
  "--platform manylinux2014_armv7l --python-version 311"; do
  if python3 -m pip download psutil -d "$OUT" --only-binary=:all: --no-deps $args 2>/dev/null; then
    echo "  ok: $args"
  else
    echo "  skip（无对应 wheel）: $args"
  fi
done
echo "==> 当前文件:"
ls -la "$OUT"/*.whl 2>/dev/null || echo "（无 .whl）"
