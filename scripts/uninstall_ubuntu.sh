#!/usr/bin/env bash
# ==============================================================================
# NVIDIA RTX 30系 GPU Unlock 一键卸载与回滚脚本 (Ubuntu / Debian)
# ==============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误: 请使用 sudo 运行此脚本: sudo bash $0"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$REPO_DIR/VERSION" 2>/dev/null || echo "1.0.0")"

echo "=== [1/4] 从 DKMS 移除 gpu-unlock 模块 ==="
if dkms status -m gpu-unlock -v "$VERSION" | grep -q "gpu-unlock"; then
    dkms remove -m gpu-unlock -v "$VERSION" --all || true
fi
rm -rf "/usr/src/gpu-unlock-${VERSION}"

echo "=== [2/4] 清理固件、modprobe 规则与 initramfs 钩子 ==="
rm -rf /usr/lib/firmware/gpu-unlock
rm -f /usr/share/initramfs-tools/modules.d/gpu-unlock.conf
rm -f /usr/share/initramfs-tools/scripts/init-top/00_gpu_unlock
rm -f /etc/modprobe.d/gpu-unlock.conf
rm -f /usr/lib/modprobe.d/gpu-unlock.conf

echo "=== [3/4] 移除 GRUB 启动参数并更新引导 ==="
sed -i 's/ *gpu_unlock\.targets=[^ "]*//g' /etc/default/grub
grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub
update-grub

echo "=== [4/4] 重新生成 initramfs ==="
update-initramfs -u -k all

echo "✅ 已彻底卸载 gpu-unlock，重启系统 (sudo reboot) 后即恢复显卡出厂默认状态。"
