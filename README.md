# NVIDIA RTX 30系全系列 Tensor Core 满血算力解锁备份与一键部署仓库

本仓库完整备份了针对 **NVIDIA RTX 30 全系列（Ampere 架构：GA102 / GA103 / GA104 / GA106）** 消费级显卡的 **FP16 / BF16 / TF32（带 FP32 累加）Tensor Core 算力解锁驱动模块、预生成离线固件资产（Prebuilt Firmware Assets）以及 Ubuntu/Debian 一键部署脚本**。

> **为什么建立此备份仓库？**
> 1. **彻底离线可用（免下载 326MB 外部包）**：上游项目构建时需临时从外部服务器下载 326 MB 的历史驱动包并提取固件；本仓库在 [`prebuilt_assets/`](./prebuilt_assets) 及 GitHub Releases 中直接完整备份了已提取并通过 SHA-256 校验的全套通用固件（`booter_load_ga102.bin`、`gsp_ga10x.bin`、`gsp_boot_ga102.bin`、`gsp_boot_desc_ga102.bin`、`v67-ga102-610.43.03.bin`），即使未来外部链接失效也可 100% 离线部署。
> 2. **支持全系已破解的 RTX 30 系列显卡**：底层固件与内核模块并非仅针对单一型号，而是通用支持所有在列的 **GA102、GA103、GA104、GA106** 芯片（共 47 个 PCI 设备 ID）。
> 3. **修复 Ubuntu 24.04 `initramfs` 抢先加载冲突（`-16 / -EBUSY`）**：内置 [`scripts/deploy_ubuntu.sh`](./scripts/deploy_ubuntu.sh) 一键脚本，自动配置 `modprobe softdep` 与 `init-top/00_gpu_unlock` 钩子，并自动为系统中所有已安装内核头文件的 Linux 内核编译 DKMS 模块。

---

## 一、 解锁原理简介

NVIDIA 在消费级 GeForce RTX 30 系列显卡上通过固件速度选择寄存器（Speed Selectors），人为将 **FP16 / BF16 混合精度矩阵乘加运算（FP32 Accumulate）** 及 **TF32** 的指令发射速率限制在了专业卡（如 RTX A6000）的 **一半（50%）**。

本方案（基于开源项目 `Zagitta/gpu-unlock`）：
* **不刷写 VBIOS、不修改官方 NVIDIA 驱动**；
* 通过一个位于 `initramfs` 阶段的早期 Linux 内核模块（`gpu_unlock.ko`），在系统启动、**官方 `nvidia.ko` 驱动绑定显卡之前**抢先运行；
* 利用 SEC2 Booter 机制将硬件速度选择寄存器写入满血值（`SS0 = 0x88888888`，`SS1 = 0x8`），随后执行一次 PCIe 功能级重置（FLR, Function Level Reset）清理现场；
* 重置完成后，原版 NVIDIA 官方驱动正常加载并接管显卡，后续升级 NVIDIA 驱动或 Linux 内核无需重新打补丁。

---

## 二、 支持的 RTX 30 系列显卡列表

内核模块 [`kernel/gpu_unlock/main.c`](./kernel/gpu_unlock/main.c) 与 [`prebuilt_assets/`](./prebuilt_assets) 中的通用固件支持以下全部 **Ampere 架构 GeForce 显卡**（执行时可通过 `gpu_unlock.targets=all` 自动识别解锁，并自动忽略机器上的老架构副卡如 10 系/20 系）：

| 核心代号 | 显卡型号 | PCI Device ID | 解锁状态 | 实测 BF16 GEMM 算力增幅 |
| :--- | :--- | :---: | :---: | :---: |
| **GA102** | **RTX 3080 20GB (扩容版 / 本机实测)** | `10de:2206` | ✅ **完美解锁** | **+73.4%** (`64.81 -> 112.36 TFLOPS`) |
| **GA102** | **RTX 3080 10GB / 12GB** | `10de:2206` / `220a` / `2216` | ✅ 完美解锁 | +70% ~ +73% |
| **GA102** | **RTX 3090 Ti 24GB** | `10de:2203` | ✅ 完美解锁 | +68% ~ +80% (`87.5 -> 157.4 TFLOPS`) |
| **GA102** | **RTX 3090 24GB** | `10de:2204` | ✅ 完美解锁 | +25% ~ +67% (取决于功耗墙上限) |
| **GA102** | **RTX 3080 Ti 12GB** | `10de:2208` | ✅ 支持解锁 | 约 +60% ~ +75% |
| **GA104** | **RTX 3070 Ti 8GB** | `10de:2482` | ✅ 完美解锁 | 约 +75% ~ +85% |
| **GA104** | **RTX 3070 / 3070 LHR 8GB** | `10de:2484` / `2488` | ✅ 完美解锁 | +73% ~ +84% |
| **GA104** | **RTX 3060 Ti / LHR 8GB** | `10de:2486` / `2489` / `24c9` | ✅ 支持解锁 | 约 +70% ~ +80% |
| **GA106** | **RTX 3060 12GB / LHR** | `10de:2503` / `2504` | ✅ 完美解锁 | 约 +80% |
| **GA106M** | **RTX 3060 Laptop 6GB (笔记本)** | `10de:2520` / `2560` | ✅ 完美解锁 | +56% ~ +60% |
| **GA103** | **RTX 3080 Ti Laptop / GA103 桌面端** | `10de:2414` | ✅ 已内置支持 | 待更多报告 |

> **注**：源码 `supported_ids[]` 中完整包含以下 PCI ID：
> * **GA102**: `0x2200`, `0x2203`, `0x2204`, `0x2205`, `0x2206`, `0x2207`, `0x2208`, `0x220a`, `0x220d`, `0x2216`, `0x222b`, `0x222f`
> * **GA103**: `0x2414`
> * **GA104**: `0x2480`, `0x2482`, `0x2483`, `0x2484`, `0x2486`, `0x2487`, `0x2488`, `0x2489`, `0x248a`, `0x248c`, `0x248d`, `0x248e`, `0x249c`, `0x249d`, `0x249f`, `0x24a0`, `0x24a4`, `0x24ac`, `0x24ad`, `0x24af`, `0x24bf`, `0x24c0`, `0x24c7`, `0x24c8`, `0x24c9`, `0x24dc`, `0x24dd`, `0x24df`, `0x24e0`
> * **GA106 / GA106M**: `0x2501`, `0x2503`, `0x2504`, `0x2505`, `0x2507`, `0x2508`, `0x2509`, `0x2520`, `0x252f`, `0x2544`, `0x2560`

---

## 三、 本机（`spark` 服务器 RTX 3080 20GB）实测基准数据

测试环境：Ubuntu 24.04.3 LTS，Linux Kernel `7.0.0-38-generic`，NVIDIA Driver `535.309.01`，PyTorch `2.8.0+cu128`。
测试负载：`8192 × 8192 × 8192` 稠密矩阵乘法（[`scripts/bench_gemm.py`](./scripts/bench_gemm.py)）：

| 测试项目 | 解锁前中位数耗时 | 解锁后中位数耗时 | 解锁前中位数算力 | 解锁后中位数算力 (峰值) | 实测提升幅度 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **BF16 (FP32 Accumulate)** | `16.96 ms` | **`9.79 ms`** | `64.81 TFLOPS` | **`112.36 TFLOPS`** (`113.42`) | **🚀 +73.4%** |
| **FP16 (FP32 Accumulate)** | `17.22 ms` | **`10.04 ms`** | `63.85 TFLOPS` | **`109.51 TFLOPS`** (`110.98`) | **🚀 +71.5%** |
| **TF32 (FP32 Accumulate)** | `34.64 ms` | **`20.25 ms`** | `31.74 TFLOPS` | **`54.29 TFLOPS`** (`54.44`) | **🚀 +71.0%** |
| **FP32 (CUDA Core 标准单精度对照)** | `51.36 ms` | `51.06 ms` | `21.41 TFLOPS` | `21.53 TFLOPS` (`21.67`) | `+0.6%` (正常误差) |

---

## 四、 快速部署指南（Ubuntu / Debian 推荐）

### 1. 前置检查
确保主板 BIOS 已关闭 **Secure Boot**，并安装有基础编译工具与当前内核头文件：
```bash
mokutil --sb-state   # 应显示 SecureBoot disabled
sudo apt-get update && sudo apt-get install -y build-essential dkms linux-headers-$(uname -r) zstd python3
```

### 2. 克隆本仓库并记录解锁前基准算力（可选）
```bash
git clone https://github.com/huangyixin447/rtx30-gpu-unlock-backup.git
cd rtx30-gpu-unlock-backup

# 使用你的 PyTorch 环境跑一次解锁前基准（结果自动保存至 scripts/baseline_before.json）
python3 scripts/bench_gemm.py
```

### 3. 执行一键离线部署脚本
本仓库内置的 [`scripts/deploy_ubuntu.sh`](./scripts/deploy_ubuntu.sh) 会自动从 [`prebuilt_assets/`](./prebuilt_assets) 解压固件、跑通校验、为系统内所有带头文件的内核安装 DKMS 模块、写入防抢占钩子并更新 GRUB：

```bash
# 方式 A：自动解锁机器上所有受支持的 30 系显卡（推荐，会自动忽略非 30 系显卡）
sudo bash scripts/deploy_ubuntu.sh all

# 方式 B：仅解锁指定 PCI 总线地址的显卡（可通过 lspci -D | grep -i nvidia 查看）
sudo bash scripts/deploy_ubuntu.sh 0000:01:00.0
```

安装完成后重启服务器：
```bash
sudo reboot
```

### 4. 重启后验证解锁状态与算力对比
```bash
# 1. 查看内核日志，确认输出 "gpu_unlock: unlocked"
journalctl -k -b | grep gpu_unlock

# 2. 再次运行基准测试脚本，自动输出 Before vs After 算力对比
python3 scripts/bench_gemm.py
```

正常的成功内核日志如下：
```text
pci 0000:01:00.0: selector read: SS0=0x50170115 expected_unlock=0x88888888
pci 0000:01:00.0: selector write: SS0=0x88888888
pci 0000:01:00.0: selector read: SS1=0x5 expected_unlock=0x8
pci 0000:01:00.0: selector write: SS1=0x8
pci 0000:01:00.0: post-FLR SEC2 reset released, GSP halted, BME=0 pending=0 WPR2=1ffffe00:00000000 SS0=88888888 SS1=00000008
pci 0000:01:00.0: gpu_unlock: unlocked
```

---

## 五、 常见发行版通用构建方式（Arch / Fedora / RHEL）

如果你使用的是 Arch Linux 或 Fedora/RHEL，也可以直接使用仓库根目录下的 `Makefile`：
```bash
# 先将本仓库内置的离线固件解压到 ~/.cache/gpu-unlock/assets（免去下载 326MB 原始包）
mkdir -p ~/.cache/gpu-unlock/assets
cat prebuilt_assets/prebuilt-assets-610.43.03.tar.zst.part_* | zstd -d | tar -C ~/.cache/gpu-unlock/assets --strip-components=1 -xf -

# 或直接使用上游在线拉取构建安装：
make install
```
随后在对应引导器中加入内核启动参数 `gpu_unlock.targets=all`（详见 [`README_UPSTREAM.md`](./README_UPSTREAM.md)）。

---

## 六、 踩坑记录与排错指南（重要）

### 1. 为什么重启后 `journalctl -k -b | grep gpu_unlock` 报错 `unlock failed (-16)`？
* **原因**：错误码 `-16` 代表 `-EBUSY`（显卡已被 `nvidia` 驱动提前绑定）。在 Ubuntu 24.04 等系统中，`framebuffer-nvidia` 会把 `nvidia.ko` 打入 `initramfs`，而 `initramfs` 启动时先执行 `/scripts/init-top/udev`（通过 PCI 硬件 ID 自动触发 `modprobe nvidia`），之后才执行 `load_modules` 去加载 `/usr/share/initramfs-tools/modules.d/gpu-unlock.conf`。
* **解决办法**：本仓库的 [`scripts/deploy_ubuntu.sh`](./scripts/deploy_ubuntu.sh) 已内置双重修复：
  1. 在 `/etc/modprobe.d/gpu-unlock.conf` 与 `/usr/lib/modprobe.d/gpu-unlock.conf` 写入 `softdep nvidia pre: gpu_unlock`；
  2. 在 `/usr/share/initramfs-tools/scripts/init-top/00_gpu_unlock` 写入早期加载脚本，确保在 `udev` 启动前优先加载 `gpu_unlock`。

### 2. 系统有待重启生效的新内核（如 `apt upgrade` 后）导致重启后模块未加载？
* **原因**：如果只针对当前 `uname -r` 编译 DKMS 模块，重启时 GRUB 默认进入更高版本的新内核，导致新内核的 `initramfs` 中没有 `gpu_unlock.ko`。
* **解决办法**：[`scripts/deploy_ubuntu.sh`](./scripts/deploy_ubuntu.sh) 已自动遍历 `/lib/modules/*/build` 为所有已安装头文件的内核构建 DKMS 模块并执行 `update-initramfs -u -k all`。

### 3. 如何一键卸载并恢复出厂默认状态？
直接运行本仓库提供的一键卸载脚本并重启即可：
```bash
sudo bash scripts/uninstall_ubuntu.sh
sudo reboot
```

---

## 七、 在 PyTorch / 深度学习训练中吃满解锁算力的技巧

1. **开启 TF32 矩阵乘法（零代码改动提速 2.5 倍）**：
   PyTorch 1.12+ 默认关闭了 `matmul` 的 TF32，如果不开启，`float32` 矩阵乘法只会走 `21.5 TFLOPS` 的普通 CUDA Core。在训练脚本开头加上：
   ```python
   import torch
   torch.set_float32_matmul_precision('high')  # 自动调用解锁后的 54.3 TFLOPS TF32 Tensor Core
   ```
   或者在环境变量中设置 `NVIDIA_TF32_OVERRIDE=1`。
2. **开启 BF16 混合精度（吃满 112+ TFLOPS 算力）**：
   ```python
   with torch.amp.autocast('cuda', dtype=torch.bfloat16):
       output = model(inputs)
       loss = criterion(output, targets)
   ```
3. **多卡混插机器（如 3080 + 旧亮机卡 1050 Ti）全局自动配置**：
   可在对应 Conda 环境的 `lib/python3.x/site-packages/sitecustomize.py` 中写入：
   ```python
   import os
   os.environ.setdefault("CUDA_VISIBLE_DEVICES", "0")
   os.environ.setdefault("NVIDIA_TF32_OVERRIDE", "1")
   ```

---

## 八、 目录结构说明

* [`kernel/gpu_unlock/`](./kernel/gpu_unlock/)：Linux 内核模块 C 源码与 DKMS 配置（支持 GA102/GA103/GA104/GA106 全系列）。
* [`prebuilt_assets/`](./prebuilt_assets/)：完整备份的 610.43.03 预提取固件文件及 `gsp_ga10x.bin` 离线压缩分卷。
* [`firmware/`](./firmware/)：上游固件提取与 V67 载荷生成 Python 脚本。
* [`scripts/deploy_ubuntu.sh`](./scripts/deploy_ubuntu.sh)：Ubuntu/Debian 离线一键安装与防抢占配置脚本。
* [`scripts/uninstall_ubuntu.sh`](./scripts/uninstall_ubuntu.sh)：Ubuntu/Debian 一键卸载与恢复脚本。
* [`scripts/bench_gemm.py`](./scripts/bench_gemm.py)：PyTorch 8192³ 稠密矩阵乘法（BF16/FP16/TF32/FP32）算力测试对比脚本。
* [`README_UPSTREAM.md`](./README_UPSTREAM.md)：上游原版英文说明文档。
