#!/usr/bin/env bash
# ==============================================================================
# NVIDIA RTX 30系 (GA102/GA103/GA104/GA106) Tensor Core 算力解锁一键部署脚本
# 适用系统: Ubuntu / Debian (基于 DKMS + initramfs-tools + GRUB)
#
# 用法:
#   sudo bash scripts/deploy_ubuntu.sh [TARGETS]
#
# 参数说明:
#   TARGETS: 可选，默认为 "all"（自动解锁机器上所有支持的 30 系显卡，跳过非 30 系卡）。
#            也可以指定单个或多个 PCI 地址，例如:
#            sudo bash scripts/deploy_ubuntu.sh 0000:01:00.0
# ==============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误: 请使用 sudo 运行此脚本:"
    echo "   sudo bash $0 ${1:-all}"
    exit 1
fi

TARGETS="${1:-all}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$REPO_DIR/VERSION")"
WORK_ASSETS="/tmp/gpu-unlock-assets-$$"

cleanup() {
    rm -rf "$WORK_ASSETS"
}
trap cleanup EXIT

echo "======================================================================"
echo "🚀 开始部署 NVIDIA RTX 30系 GPU Unlock (v${VERSION})"
echo "   解锁目标 (gpu_unlock.targets): ${TARGETS}"
echo "======================================================================"

echo ""
echo "=== [1/6] 准备并校验预编译固件资产 (Prebuilt Firmware Assets) ==="
mkdir -p "$WORK_ASSETS"
if ls "$REPO_DIR"/prebuilt_assets/prebuilt-assets-610.43.03.tar.zst.part_* >/dev/null 2>&1; then
    echo "-> 检测到仓库内置离线固件分卷，正在解压..."
    cat "$REPO_DIR"/prebuilt_assets/prebuilt-assets-610.43.03.tar.zst.part_* \
        | zstd -d \
        | tar -C "$WORK_ASSETS" --strip-components=1 -xf -
else
    echo "-> 未检测到离线分卷，正在从上游构建固件..."
    make -C "$REPO_DIR" ASSETS="$WORK_ASSETS" assets
fi

echo "-> 运行完整性与模拟硬件解锁测试 (make test)..."
make -C "$REPO_DIR" ASSETS="$WORK_ASSETS" test

echo ""
echo "=== [2/6] 安装固件、DKMS 源码与 initramfs 配置 ==="
make -C "$REPO_DIR" ASSETS="$WORK_ASSETS" \
    install-dkms install-firmware install-initramfs-tools install-licenses

echo ""
echo "=== [3/6] 为所有已安装内核头文件的 Linux 内核编译安装 DKMS 模块 ==="
if dkms status -m gpu-unlock -v "$VERSION" | grep -q "gpu-unlock"; then
    dkms remove -m gpu-unlock -v "$VERSION" --all || true
fi
dkms add -m gpu-unlock -v "$VERSION"

for kbuild in /lib/modules/*/build; do
    if [ -d "$kbuild" ]; then
        kver="$(basename "$(dirname "$kbuild")")"
        echo "-> 正在为内核 ${kver} 编译并安装 gpu_unlock.ko..."
        dkms build -m gpu-unlock -v "$VERSION" -k "$kver"
        dkms install -m gpu-unlock -v "$VERSION" -k "$kver"
    fi
done
dkms status -m gpu-unlock -v "$VERSION"

echo ""
echo "=== [4/6] 配置 modprobe softdep 与 initramfs 抢先加载钩子 (防 -16 EBUSY) ==="
# 解决 Ubuntu 24.04 等系统中 udev 在 initramfs 阶段先于 load_modules 拉起 nvidia 驱动导致 -EBUSY (-16) 的问题
echo "softdep nvidia pre: gpu_unlock" > /etc/modprobe.d/gpu-unlock.conf
mkdir -p /usr/lib/modprobe.d
echo "softdep nvidia pre: gpu_unlock" > /usr/lib/modprobe.d/gpu-unlock.conf

cat << 'SCRIPT' > /usr/share/initramfs-tools/scripts/init-top/00_gpu_unlock
#!/bin/sh
PREREQ=""
prereqs()
{
	echo "$PREREQ"
}
case $1 in
prereqs)
	prereqs
	exit 0
	;;
esac

/sbin/modprobe gpu_unlock || true
SCRIPT
chmod 755 /usr/share/initramfs-tools/scripts/init-top/00_gpu_unlock

echo ""
echo "=== [5/6] 更新 initramfs 镜像并验证文件打包 ==="
update-initramfs -u -k all
CURRENT_INITRD="/boot/initrd.img-$(uname -r)"
if [ -f "$CURRENT_INITRD" ]; then
    echo "-> 校验当前内核 ($CURRENT_INITRD) 中的 gpu_unlock 组件:"
    lsinitramfs "$CURRENT_INITRD" | grep -E "gpu_unlock|gpu-unlock" || true
fi

echo ""
echo "=== [6/6] 配置 GRUB 内核启动参数 ==="
cp -a /etc/default/grub "/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
if grep -q "gpu_unlock.targets=" /etc/default/grub; then
    sed -i "s/gpu_unlock\.targets=[^ \"]*/gpu_unlock.targets=${TARGETS}/g" /etc/default/grub
else
    sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 gpu_unlock.targets=${TARGETS}\"/" /etc/default/grub
fi
grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub
update-grub

echo ""
echo "======================================================================"
echo "✅ 部署全部完成！"
echo "1. 请执行 'sudo reboot' 重启服务器以使解锁生效；"
echo "2. 重启后可执行以下命令验证解锁状态："
echo "   journalctl -k -b | grep gpu_unlock"
echo "3. 可运行基准测试脚本对比算力提升："
echo "   python3 scripts/bench_gemm.py"
echo "======================================================================"
