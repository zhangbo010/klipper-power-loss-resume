# 仓库内置 psutil（wheel）

安装脚本会**优先**从本目录的 `*.whl` 用 `pip install --no-index --find-links` 装入 **Klipper 实际使用的 Python**（通常为 `~/klipper/venv`），**无需访问 PyPI**。

当前随仓库附带常见架构：

- `manylinux` **x86_64**（PC / x86 小主机）
- `manylinux` **aarch64**（树莓派 4、多数 ARM64 板卡）

若你的设备架构不在上述之列（例如 32 位 ARM），离线安装可能失败，脚本会自动回退为 **`pip install psutil`**（需网络）。

## 维护者：补充 / 更新 wheel

在可联网机器上，于仓库根目录执行：

```bash
bash install/download-vendor-psutil.sh
```

或手动：

```bash
mkdir -p vendor/psutil
pip download psutil -d vendor/psutil --only-binary=:all: --no-deps \
  --platform manylinux2014_aarch64 --python-version 311
pip download psutil -d vendor/psutil --only-binary=:all: --no-deps \
  --platform manylinux2010_x86_64 --python-version 311
```

wheel 文件名中的 **`cp36-abi3`** 表示与 **Python 3.6+** 兼容（含 Klipper 常见 3.9 / 3.11 venv）。
