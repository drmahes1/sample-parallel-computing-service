#!/usr/bin/env bash
#
# Run bench.py while capturing DCGM counters in parallel.
# All artefacts land in $PWD/<job-id>/.
#
# Intended to be launched by a Slurm sbatch script that cd's into the target
# /fsx/results/<name>/<bench-dir> first.

set -euo pipefail

JOB_ID="${SLURM_JOB_ID:-local-$(date +%s)}"
OUTDIR="$(pwd)/${JOB_ID}"
mkdir -p "${OUTDIR}"
cd "${OUTDIR}"

echo "=== capture.sh ==="
echo "hostname:  $(hostname)"
echo "outdir:    ${OUTDIR}"
echo "gpu:       $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
echo

# DCGM field IDs:
#   203  gpu_utilization (%)
#   252  framebuffer_memory_used (MiB)
#   1001 sm_active (0..1 fraction)
#   1002 sm_occupancy (0..1 fraction)
#   1004 tensor_active (0..1 fraction)
#   140  memory_temp (degC)
#   150  gpu_temp (degC)
#   155  power_usage (W)
#
# dcgmi dmon samples at a default interval (~1s) and writes one line per sample
# per GPU. We redirect to a file.
#
# Slurm sets CUDA_VISIBLE_DEVICES for the job which makes dcgmi refuse to emit
# counters (it confuses dcgmi's idea of which GPUs exist). Unset it only for
# the dcgmi subshell - the benchmark still needs it so keep it in the parent.
echo "Starting dcgmi dmon in background ..."
(
    unset CUDA_VISIBLE_DEVICES
    exec dcgmi dmon -e 203,252,1001,1002,1004,150,155
) > dcgm.log 2>&1 &
DCGM_PID=$!

# Make sure we stop dcgmi on exit.
cleanup() {
    if kill -0 "${DCGM_PID}" 2>/dev/null; then
        kill "${DCGM_PID}" || true
        wait "${DCGM_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Run the benchmark. We assume caller activated the venv already.
python3 ~/bench.py --output "${OUTDIR}/results.csv" | tee bench.stdout

echo
echo "=== done ==="
echo "results:    ${OUTDIR}/results.csv"
echo "dcgm log:   ${OUTDIR}/dcgm.log"
echo "stdout:     ${OUTDIR}/bench.stdout"
