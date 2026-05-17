"""
Plot benchmark results locally after downloading them from S3.

Expects a local directory with results.csv (and optionally dcgm.log). Renders:
  - tflops_vs_size.png   (one line per dtype)
  - gpu_timeseries.png   (GPU util + temp + power over time, if dcgm.log exists)

Usage:
    # Grab the run artefacts first:
    aws s3 sync s3://drmahes-pcs-gpu-benchmarking/drmahes/bench-g6e/<job-id>/ ./run/

    python3 plot.py ./run/
"""

import argparse
import re
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def plot_tflops(run_dir: Path) -> None:
    csv = run_dir / "results.csv"
    if not csv.exists():
        print(f"[skip] no results.csv in {run_dir}", file=sys.stderr)
        return

    df = pd.read_csv(csv)
    df = df[df["tflops"] != "OOM"].copy()
    df["tflops"] = df["tflops"].astype(float)
    df["size"] = df["size"].astype(int)

    plt.figure(figsize=(9, 5))
    for dtype, sub in df.groupby("dtype"):
        sub = sub.sort_values("size")
        plt.plot(sub["size"], sub["tflops"], marker="o", label=dtype)

    device = df["device"].iloc[0]
    plt.xlabel("matmul size (N x N)")
    plt.ylabel("TFLOPS (achieved)")
    plt.title(f"Matmul TFLOPS on {device}")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.xscale("log", base=2)
    out = run_dir / "tflops_vs_size.png"
    plt.tight_layout()
    plt.savefig(out, dpi=150)
    print(f"wrote {out}")


def parse_dcgm_log(log_path: Path) -> pd.DataFrame:
    """Parse the tabular output of `dcgmi dmon`.

    Layout (7 data columns requested with -e 203,252,1001,1002,1004,150,155):

        #Entity   GPUTL   FBUSD   SMACT   SMOCC   TENSO   GPUT    POWR
        ID
        GPU 0     0       500     0.005   0.003   0.000   32      51.3

    A couple of quirks:
    - The header is split over two lines (real header + "ID" on its own line).
    - Each data row starts with "GPU N" (two whitespace-separated tokens) then
      N numeric columns.
    - dcgmi sometimes re-prints the header periodically when the terminal is
      resized; we ignore any non-data rows after the first.
    """
    lines = [l for l in log_path.read_text().splitlines() if l.strip()]

    # Find the first header row.
    header_idx = None
    for i, line in enumerate(lines):
        if line.lstrip().startswith("#Entity"):
            header_idx = i
            break
    if header_idx is None:
        return pd.DataFrame()

    header_tokens = re.split(r"\s+", lines[header_idx].strip())
    # Drop '#Entity' and optional 'ID' label.
    data_cols = [t for t in header_tokens[1:] if t != "ID"]

    rows = []
    for line in lines[header_idx + 1:]:
        toks = re.split(r"\s+", line.strip())
        # Expect "GPU", "<N>", then len(data_cols) numeric columns.
        if len(toks) < 2 + len(data_cols):
            continue
        if toks[0] != "GPU":
            continue
        try:
            entity = f"{toks[0]} {toks[1]}"
            vals = [float(v) for v in toks[2:2 + len(data_cols)]]
        except ValueError:
            continue
        rows.append([entity] + vals)

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows, columns=["entity"] + data_cols)
    df["t"] = range(len(df))  # synthetic time axis (samples are ~1 Hz)
    return df


def plot_dcgm(run_dir: Path) -> None:
    log = run_dir / "dcgm.log"
    if not log.exists():
        print(f"[skip] no dcgm.log in {run_dir}", file=sys.stderr)
        return

    df = parse_dcgm_log(log)
    if df.empty:
        print(f"[skip] empty/unparseable dcgm.log in {run_dir}", file=sys.stderr)
        return

    fig, axes = plt.subplots(3, 1, figsize=(9, 7), sharex=True)

    # DCGM column naming differs across versions. Try known aliases.
    util_col = next((c for c in ("GPUTL", "GPUT", "SMACT") if c in df.columns), None)
    power_col = next((c for c in ("POWER", "POWR") if c in df.columns), None)
    temp_col = next((c for c in ("TMPTR", "GPUT") if c in df.columns), None)

    if util_col:
        axes[0].plot(df["t"], df[util_col], color="C0")
        axes[0].set_ylabel(f"GPU util (%) - {util_col}")
        axes[0].grid(True, alpha=0.3)

    if power_col:
        axes[1].plot(df["t"], df[power_col], color="C1")
        axes[1].set_ylabel(f"Power (W) - {power_col}")
        axes[1].grid(True, alpha=0.3)

    if temp_col:
        axes[2].plot(df["t"], df[temp_col], color="C3")
        axes[2].set_ylabel(f"Temp (C) - {temp_col}")
        axes[2].grid(True, alpha=0.3)

    axes[-1].set_xlabel("sample index (~1 Hz)")
    fig.suptitle("DCGM timeseries during benchmark")
    fig.tight_layout()
    out = run_dir / "gpu_timeseries.png"
    fig.savefig(out, dpi=150)
    print(f"wrote {out}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir", help="directory containing results.csv (+ dcgm.log)")
    args = ap.parse_args()
    run_dir = Path(args.run_dir)
    plot_tflops(run_dir)
    plot_dcgm(run_dir)


if __name__ == "__main__":
    main()
