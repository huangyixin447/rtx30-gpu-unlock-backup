#!/usr/bin/env python3
"""
NVIDIA RTX 30系 (Ampere) Tensor Core FP16 / BF16 / TF32 算力基准测试脚本
测试方法: 8192 x 8192 x 8192 稠密矩阵乘法 (Dense GEMM)
支持自动保存解锁前基准 (baseline_before.json) 并在解锁后自动打印对比增幅。
"""
import os
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "0")
import json
import statistics
import torch


def bench_matmul(dtype, N=8192, warmup=15, iters=50, allow_tf32=False, fp16_reduced_accum=False):
    torch.backends.cuda.matmul.allow_tf32 = allow_tf32
    torch.backends.cuda.matmul.allow_fp16_reduced_precision_reduction = fp16_reduced_accum
    torch.backends.cuda.matmul.allow_bf16_reduced_precision_reduction = False

    device = torch.device("cuda:0")
    A = torch.randn((N, N), device=device, dtype=dtype)
    B = torch.randn((N, N), device=device, dtype=dtype)

    for _ in range(warmup):
        C = torch.matmul(A, B)
    torch.cuda.synchronize(device)

    times = []
    start_evt = torch.cuda.Event(enable_timing=True)
    end_evt = torch.cuda.Event(enable_timing=True)

    for _ in range(iters):
        start_evt.record()
        C = torch.matmul(A, B)
        end_evt.record()
        torch.cuda.synchronize(device)
        times.append(start_evt.elapsed_time(end_evt) / 1000.0)

    flops = 2.0 * (N ** 3)
    median_t = statistics.median(times)
    min_t = min(times)
    median_tflops = (flops / median_t) / 1e12
    peak_tflops = (flops / min_t) / 1e12
    del A, B, C
    torch.cuda.empty_cache()
    return {
        "median_ms": round(median_t * 1000, 3),
        "median_tflops": round(median_tflops, 2),
        "peak_tflops": round(peak_tflops, 2),
    }


def main():
    if not torch.cuda.is_available():
        raise RuntimeError("未检测到可用的 CUDA GPU，请检查 PyTorch 与驱动安装。")

    device_name = torch.cuda.get_device_name(0)
    props = torch.cuda.get_device_properties(0)
    print("====================================================================================")
    print(f"GPU 0: {device_name} ({props.total_memory // (1024 * 1024)} MiB)")
    print(f"PyTorch: {torch.__version__}, CUDA: {torch.version.cuda}")
    print("Matrix Size: 8192 x 8192 x 8192 (Dense GEMM)")
    print("====================================================================================")

    tests = [
        ("BF16 (FP32 Accumulate) [解锁核心指标]", torch.bfloat16, False, False),
        ("FP16 (FP32 Accumulate) [解锁核心指标]", torch.float16,  False, False),
        ("TF32 (FP32 Accumulate) [解锁核心指标]", torch.float32,  True,  False),
        ("FP32 (CUDA Core 标准单精度对照)",        torch.float32,  False, False),
    ]

    results = {}
    print(f"{'测试项目':<38} | {'中位数耗时':<10} | {'中位数算力':<14} | {'峰值算力':<12}")
    print("-" * 84)
    for name, dtype, tf32, fp16_red in tests:
        res = bench_matmul(dtype, N=8192, allow_tf32=tf32, fp16_reduced_accum=fp16_red)
        results[name] = res
        print(
            f"{name:<38} | {res['median_ms']:>7.2f} ms | "
            f"{res['median_tflops']:>8.2f} TFLOPS | {res['peak_tflops']:>8.2f} TFLOPS"
        )

    baseline_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "baseline_before.json")
    if not os.path.exists(baseline_path):
        with open(baseline_path, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, ensure_ascii=False)
        print(f"\n[已保存首次测试基准数据至 {baseline_path}]")
    else:
        with open(baseline_path, "r", encoding="utf-8") as f:
            before = json.load(f)
        print("\n====================== 解锁前后对比 (Before vs After) ======================")
        for name, res in results.items():
            if name in before:
                b_tf = before[name]["median_tflops"]
                a_tf = res["median_tflops"]
                gain = ((a_tf - b_tf) / b_tf) * 100.0 if b_tf > 0 else 0.0
                print(f"{name:<38}: {b_tf:>6.2f} -> {a_tf:>6.2f} TFLOPS ({gain:+.1f}%)")


if __name__ == "__main__":
    main()
