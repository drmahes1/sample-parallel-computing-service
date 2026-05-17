"""
Simple GPU matmul benchmark.

Sweeps matrix size and dtype, measures achieved TFLOPS per iteration,
writes timings to results.csv in the current directory.

Usage:
    python3 bench.py [--warmup N] [--iters N] [--sizes 1024,2048,...]
"""

import argparse
import csv
import os
import socket
import time

import torch

DEFAULT_SIZES = [1024, 2048, 4096, 8192, 12288, 16384]
DEFAULT_DTYPES = ["float32", "tf32", "bfloat16", "float16"]


def matmul_tflops(n: int, dtype_name: str, warmup: int, iters: int) -> float:
    torch.cuda.empty_cache()
    # Map dtype name to torch dtype and matmul setting.
    if dtype_name == "tf32":
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        dtype = torch.float32
    else:
        torch.backends.cuda.matmul.allow_tf32 = False
        torch.backends.cudnn.allow_tf32 = False
        dtype = getattr(torch, dtype_name)

    x = torch.randn(n, n, device="cuda", dtype=dtype)
    y = torch.randn(n, n, device="cuda", dtype=dtype)

    for _ in range(warmup):
        _ = x @ y
    torch.cuda.synchronize()

    start = time.perf_counter()
    for _ in range(iters):
        _ = x @ y
    torch.cuda.synchronize()
    elapsed = time.perf_counter() - start

    # 2 * n^3 flops per matmul.
    return iters * 2 * (n ** 3) / elapsed / 1e12


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--warmup", type=int, default=3)
    ap.add_argument("--iters", type=int, default=50)
    ap.add_argument("--sizes", type=str, default=",".join(str(s) for s in DEFAULT_SIZES))
    ap.add_argument("--dtypes", type=str, default=",".join(DEFAULT_DTYPES))
    ap.add_argument("--output", type=str, default="results.csv")
    args = ap.parse_args()

    sizes = [int(s) for s in args.sizes.split(",")]
    dtypes = args.dtypes.split(",")

    if not torch.cuda.is_available():
        raise RuntimeError("CUDA not available")

    hostname = socket.gethostname()
    device_name = torch.cuda.get_device_name(0)
    run_id = os.environ.get("SLURM_JOB_ID", str(int(time.time())))

    with open(args.output, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "run_id", "hostname", "device", "size", "dtype",
            "warmup", "iters", "tflops",
        ])
        for dtype_name in dtypes:
            for n in sizes:
                try:
                    tflops = matmul_tflops(n, dtype_name, args.warmup, args.iters)
                    print(f"{dtype_name:>8} n={n:>5}: {tflops:7.1f} TFLOPS")
                    w.writerow([run_id, hostname, device_name, n, dtype_name,
                                args.warmup, args.iters, f"{tflops:.2f}"])
                    f.flush()
                except torch.cuda.OutOfMemoryError:
                    print(f"{dtype_name:>8} n={n:>5}: OOM")
                    w.writerow([run_id, hostname, device_name, n, dtype_name,
                                args.warmup, args.iters, "OOM"])
                    f.flush()
                    torch.cuda.empty_cache()


if __name__ == "__main__":
    main()
