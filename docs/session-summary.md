# Session summary — GPU benchmarking cluster build

Written 17 May 2026 to preserve context across Kiro sessions.

## Where we are

Cluster is **deployed and working**. SSH first-try works for LDAP user
`drmahes`. End-to-end benchmark pipeline (sbatch -> DCGM capture -> Lustre ->
S3 via DRA -> laptop plot) validated. Code committed and pushed to
`https://github.com/drmahes1/sample-parallel-computing-service` branch
`DLAMI`. The fork has `origin = drmahes1`, `upstream = aws-samples`.

## Cluster details (currently deployed)

- **Account**: 726556303455 (Isengard, sim-user)
- **Region/AZ**: us-west-2 / us-west-2c
- **PCS cluster id**: `pcs_2tkddgg8fb`
- **Login instance**: c6i.4xlarge (c6a.4xlarge ran out of capacity, switched)
- **GPU queues**:
  - `g6e` -> g6e.2xlarge (1x L40S, on-demand, max 2)
  - `g7e` -> g7e.12xlarge (2x RTX PRO 6000 Blackwell, spot, max 2)
- **AMI**: DLAMI Base OSS AL2023 pinned to `20260121`
  - NVIDIA driver 580.126.09
  - CUDA 12.6/12.8/12.9 (default)/13.0
  - DCGM 4.5.3 running as `nvidia-dcgm.service`
  - nsys 2025.6.1, ncu 2025.2.1, aws-ofi-nccl 1.17.2
  - Python 3.12
- **FSx OpenZFS**: 256 GiB SINGLE_AZ_1, 256 MB/s throughput (`/home`, `/sw`)
- **FSx Lustre**: 2400 GiB PERSISTENT_2 SSD, 125 MB/s/TiB, EFA off (forced by
  the EFA-on minimum-capacity rule)
- **DRA**: `/fsx/results` <-> `s3://drmahes-pcs-gpu-benchmarking/` (bucket root)
  bidirectional NEW/CHANGED/DELETED
- **Tags**: `auto-delete=no`, `Project=pcs-gpu-benchmarking`,
  `Owner=drmahes` applied to all managed resources via `default_tags` on the
  aws provider, plus explicit `tags` on awscc PCS resources.

## What's actually different from upstream Tim repo

Beyond the obvious DLAMI base + GPU queues, we did a lot of cluster
hardening that took several iterations:

1. **AMI cloud-init cleanup step** — fixes empty `/home/ec2-user/.ssh/authorized_keys`
   on first boot. Was the cause of "ssh ec2-user fails" issues. See the
   `CleanupCloudInitState` step in `modules/ami/pcs-component.yaml`.
2. **Non-root GPU profiling** (`/etc/modprobe.d/nvidia-profiling.conf` +
   dracut). Required for ncu/nvprof to work in user jobs.
3. **Auto-detected DCGM service enable**. Tries `nvidia-dcgm.service`,
   `dcgm.service`, `nv-hostengine.service`. Currently the first match.
4. **Component/recipe versions auto-bumped from filemd5** of the YAML +
   cwa-config.json. Stops "I edited the bake script and nothing changed".
5. **PCS resource `lifecycle.ignore_changes`** for awscc spurious drift
   (cluster_id, slurm_configuration, spot_options).
6. **Lustre EFA disabled** (forced by minimum capacity rule of 38400 GiB).
7. **NAT Gateway + EIP** kept (different design point from CPU sample).
8. **Two S3 buckets**: build (managed by Terraform, ephemeral) and
   benchmarking (data source only, customer-managed, pre-create with CLI).
9. **CloudWatch Agent** installed on AMI but only started by compute-node
   launch templates. Login node has CWA idle.
10. **Per-instance-type EFA toggle** in launch templates — g6e.2xlarge does
    not support EFA, larger sizes do. Driven by `efa_supported` from the
    `aws_ec2_instance_type` data source.
11. **AMI distribution** to account `905784713722` (left over from Tim's
    config — should probably be removed for customer use).

## Known limitations still real

These are documented in `README.md` and `docs/ssh-troubleshooting.md`:

1. **AMI rebake requires manual queue delete dance**:
   ```sh
   aws pcs list-queues --region us-west-2 --cluster-identifier <cluster-id> \
     --query 'queues[].id' --output text
   # Delete each queue, then:
   terraform state rm 'module.pcs.awscc_pcs_queue.gpu["g6e.2xlarge"]' \
                      'module.pcs.awscc_pcs_queue.gpu["g7e.12xlarge"]'
   terraform apply
   ```
2. **Image Builder pipeline orphan after bake failure**:
   ```sh
   aws imagebuilder delete-image-pipeline --region us-west-2 \
     --image-pipeline-arn arn:aws:imagebuilder:us-west-2:<account>:image-pipeline/wx-x86
   ```
3. **AZ instance capacity** flakes. c6a.4xlarge / c6a.8xlarge in us-west-2c
   have been intermittently unavailable. c6i.4xlarge currently working.

## Pipeline integration (sibling project)

The other Kiro project is at `~/myDevelopments/fusion/.kiro/specs/gpu-benchmark-pipeline/`
(if I remember the path). They want us to publish absolute paths to GPU
tools so they don't depend on PATH.

**Pending AMI change** (in code but NOT YET DEPLOYED — needs a rebake):
A `PublishPipelinePaths` step in `modules/ami/pcs-component.yaml` writes
`/etc/profile.d/pipeline-paths.sh` exporting:
```
PIPELINE_NSYS=/opt/nvidia/nsight-systems/2025.6.1/bin/nsys
PIPELINE_NCU=/usr/local/cuda-12.9/bin/ncu
PIPELINE_NVCC=/usr/local/cuda-12.9/bin/nvcc
PIPELINE_CUDA_DEMO_SUITE=/usr/local/cuda-12.9/extras/demo_suite
PIPELINE_DCGMI=/usr/bin/dcgmi
```
This change is on disk but not applied. Apply it when batched with anything
else the pipeline project asks for, to avoid multiple ~50-min rebakes.

**Things pipeline asked for that we pushed back on**:
- LIKWID — not relevant for GPU-only single-node benchmarking.
- OSU Micro-Benchmarks — MPI-CPU, not for GPU.
- nccl-tests pre-built in AMI — pipeline owns the build (`git clone NVIDIA/nccl-tests && make` at job start).

**Things still owed to pipeline once they have specifics**:
- Compute-role IAM policies (3 of them: local artifact write, cross-region
  records writer to us-east-2 records bucket, secrets-manager tag-scoped).
  Blocked on: pipeline providing records bucket name + Application tag value.
- Slurm prolog or env injection of 5 `PIPELINE_*_BUCKET / *_REGION / *_FS_PATH`
  env vars on compute nodes. The `pipeline-paths.sh` work above is partially
  this, but the bucket/region values still need to come from pipeline team.

## Files of interest

- `terraform.tfvars` — git-ignored, contains `ssh_key`, `users`, `instance_login`
- `users.ldif` — git-ignored, currently has only `drmahes` user
- `providers.tf` — `default_tags` map at top, edit to change tags for fork
- `main.tf` — note `data "aws_s3_bucket" "benchmarking"` (bucket NOT managed)
- `modules/ami/pcs-component.yaml` — Image Builder bake recipe
- `modules/ami/cwa-config.json` — CloudWatch Agent config (compute-only metrics)
- `modules/pcs/main.tf` — PCS cluster, node groups, queues, launch templates
- `modules/pcs/templates/*.userdata.tpl` — per-instance-type bootstrap
- `benchmarks/g6e/` — sample matmul benchmark + DCGM capture + plotter
- `docs/ssh-troubleshooting.md` — diagnostic runbook
- `README.md` — customer-facing quickstart

## Apply / destroy procedure

**Fresh apply** (from empty state):
```sh
# 1. Pre-create benchmarking bucket
aws s3api create-bucket --bucket "$BUCKET" --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2
aws s3api put-bucket-tagging --bucket "$BUCKET" \
  --tagging 'TagSet=[{Key=auto-delete,Value=no}]'

# 2. Create terraform.tfvars + users.ldif (see README)

# 3. Apply
terraform init
terraform apply

# 4. Get login IP, SSH in
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=tag:aws:pcs:cluster-id,Values=*" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[?PublicIpAddress!=null].PublicIpAddress' \
  --output text
ssh drmahes@<that-ip>
```

**Destroy**:
```sh
# 1. Pre-delete queues (PCS ordering bug)
aws pcs list-queues --region us-west-2 --cluster-identifier "$(terraform output -raw pcs_cluster_id)" --query 'queues[].id' --output text
# delete each one with: aws pcs delete-queue --region us-west-2 ...
terraform state rm 'module.pcs.awscc_pcs_queue.gpu["g6e.2xlarge"]' \
                   'module.pcs.awscc_pcs_queue.gpu["g7e.12xlarge"]'

# 2. Destroy
terraform destroy

# 3. Benchmarking bucket survives (data source, not managed)
```

## Open work

In rough priority order, none urgent:

1. Apply the `PublishPipelinePaths` AMI change (when batched with other
   pipeline asks). ~50 min rebake.
2. Sample NCCL benchmark on g7e (write `benchmarks/g7e/`).
3. Add `Makefile` with `safe-apply` / `safe-destroy` targets that include
   the queue-delete dance.
4. Wire pipeline IAM policies + records bucket env vars (when pipeline
   provides specs).
5. Move LDAP to public subnet so it isn't dependent on NAT readiness at
   first boot. Currently works but is fragile.
6. Remove the leftover `launch_permission { user_ids = ["905784713722"] }`
   AMI cross-account share from Tim's repo.
