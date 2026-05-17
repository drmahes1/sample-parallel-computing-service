# Single-GPU benchmark on g6e

End-to-end example showing how to:

1. Run a PyTorch matmul sweep on a compute node
2. Capture GPU counters with `dcgmi dmon` in parallel
3. Land the outputs on `/fsx/results/$USER/bench-g6e/$JOBID/` which
   auto-syncs to S3 via the Lustre DRA
4. Pull from S3 and plot on your laptop

## Files

| File | Role | Where it runs |
|---|---|---|
| `bench.py` | PyTorch matmul sweep writing CSV | Compute node (inside the Slurm job) |
| `capture.sh` | Wraps `bench.py` with DCGM sampling | Compute node |
| `job.sbatch` | Slurm submission script | Login node |
| `plot.py` | Renders PNGs from CSV + dcgm.log | Your laptop |

## First-time setup

On the login node:

```sh
# One-off python venv with torch - lives on /home (OpenZFS), visible
# on all compute nodes.
python3 -m venv ~/env
source ~/env/bin/activate
pip install --upgrade pip
pip install torch --index-url https://download.pytorch.org/whl/cu129
pip install numpy pandas

# Copy benchmark files to home
scp bench.py capture.sh job.sbatch <login-node>:~/   # from your laptop
chmod +x ~/capture.sh
```

## Submit a run

```sh
# On the login node:
mkdir -p /fsx/results/$USER/bench-g6e   # PCS doesn't auto-create this
sbatch ~/job.sbatch
squeue                                   # watch state: CF (configuring) -> R (running) -> gone
```

~5 min total: ~3 min node boot, ~90 sec actual benchmark.

Output lands in `/fsx/results/$USER/bench-g6e/<jobid>/`:

- `results.csv` — one row per (dtype, size)
- `dcgm.log` — GPU counters sampled ~1 Hz during the run
- `bench.stdout` — python stdout
- `../slurm-<jobid>.{out,err}` — Slurm wrappers

## Pull results to laptop and plot

On your laptop:

```sh
mkdir -p ~/bench-g6e-run
aws s3 sync s3://<benchmarking-bucket>/drmahes/bench-g6e/<jobid>/ ~/bench-g6e-run/
python3 plot.py ~/bench-g6e-run/
open ~/bench-g6e-run/tflops_vs_size.png ~/bench-g6e-run/gpu_timeseries.png
```

## Interpreting the plots

`tflops_vs_size.png` — achieved TFLOPS per dtype × matmul size. You should
see:

- **float32**: ~40 TFLOPS on L40S (peak ~91, so about 45% of peak)
- **tf32**: ~100 TFLOPS (tensor cores via TF32)
- **bfloat16 / float16**: ~250-260 TFLOPS at mid sizes (tensor cores,
  about 70% of the ~362 TFLOPS tensor-core peak)

Numbers below ~1024 are launch-overhead-dominated, above ~8192 tend to be
memory-bandwidth-limited.

`gpu_timeseries.png` — three panels: GPU utilisation, power draw, temp.
During the 24 matmul test cases you should see:

- Utilisation climb to 100% during each test, brief dips between
- Power tracking utilisation, peaking near the 350 W TDP
- Temp rising ~20 °C over the run (starts idle ~25 °C, climbs to ~55-60 °C)

If all three panels look empty, the parser didn't find known columns
(DCGM column names differ across versions). See `plot.py:parse_dcgm_log`.

## Extending

To run on `g7e` (2× RTX PRO 6000) instead:

- Edit `job.sbatch` and change `#SBATCH --partition=g6e` to `g7e`.
- Change output path if you want separate results (`bench-g7e/`).
- Everything else works the same.

To use multiple GPUs on one node, wrap the run in `torchrun`:

```bash
srun torchrun --nproc_per_node=2 bench.py --sizes 8192,16384
```

For cross-node NCCL testing, build `nccl-tests` on /fsx and run under MPI.
Not scripted here yet.
