#!/usr/bin/env bash
#SBATCH --job-name=g6e-bench
#SBATCH --partition=g6e
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:30:00
#SBATCH --output=/fsx/results/%u/bench-g6e/slurm-%j.out
#SBATCH --error=/fsx/results/%u/bench-g6e/slurm-%j.err
#
# Run the L40S matmul benchmark with DCGM counter capture.
# Outputs land in /fsx/results/<user>/bench-g6e/<job-id>/ and auto-export to S3.

set -euo pipefail

WORKDIR="/fsx/results/${USER}/bench-g6e"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

# Activate the torch venv we installed earlier.
source "${HOME}/env/bin/activate"

# Run capture.sh which wraps bench.py + dcgmi dmon.
bash "${HOME}/capture.sh"
