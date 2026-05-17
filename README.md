# AWS PCS GPU benchmarking cluster

Terraform module for deploying a small GPU benchmarking cluster on AWS
Parallel Computing Service (PCS), derived from the DLAMI branch of
[aws-samples/sample-parallel-computing-service][upstream].

[upstream]: https://github.com/aws-samples/sample-parallel-computing-service

> Status: alpha. Deploys fine on first apply. Subsequent applies that
> trigger an AMI rebake (for example, editing `modules/ami/pcs-component.yaml`)
> require a manual queue-delete workaround. See **Known limitations** below.

## What you get

- A PCS cluster with a single login node and GPU compute node groups.
- Two GPU queues (default): `g6e` (1× L40S) and `g7e` (2× Blackwell RTX PRO 6000).
- FSx OpenZFS for `/home` and `/sw` and FSx Lustre for `/fsx/results`.
- A bidirectional Data Repository Association from `/fsx/results` to an
  S3 bucket — write a file to `/fsx/results/foo/bar.csv`, it shows up in
  `s3://<benchmarking-bucket>/foo/bar.csv` within seconds.
- A custom AMI baked from the multi-CUDA DLAMI (pinned, has DCGM, CUDA
  12.6/12.8/12.9/13.0, EFA, aws-ofi-nccl, NCCL, NVIDIA Container Toolkit).
- Non-root GPU profile counter access enabled for Nsight Compute, nvprof,
  DCGM, etc.
- CloudWatch Agent pushing GPU util, memory, temp, power from compute nodes
  (compute only — login does not push metrics).
- LDAP-based user management so users SSH in as themselves, not `ec2-user`.

## Prerequisites

- AWS account with permission to create VPC, EC2, FSx, PCS, Image Builder,
  IAM, S3, Secrets Manager in the target region.
- At least two free Elastic IPs in the target region (one for the NAT
  Gateway — this module allocates exactly one).
- An SSH key pair local to your workstation. The public key is deployed to
  the cluster; you SSH in with the matching private key.
- Terraform 1.5+ and the AWS CLI v2 on your workstation.
- **Pre-create the benchmarking S3 bucket** (see below). This bucket is
  intentionally not managed by Terraform so that benchmark results survive
  cluster rebuilds.

### Pre-create the benchmarking bucket

The benchmarking bucket holds long-lived results. Terraform references it
read-only — `terraform destroy` will not touch it. Create it once, before
the first `terraform apply`:

```sh
BUCKET=<your-name>-pcs-gpu-benchmarking      # globally unique, lowercase

aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# Optional but recommended:
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

Then set `s3_bucket_benchmarking = "$BUCKET"` in your `terraform.tfvars`.
If the bucket doesn't exist, `terraform plan` fails with a clear
`NoSuchBucket` error.

> The build/staging bucket (Image Builder logs and LDAP seed) **is** managed
> by Terraform and gets recreated on every deploy. That's fine — it only
> holds disposable artefacts.

## Quick start

```sh
git clone <this repo>
cd sample-parallel-computing-service-gpu

# 1. Create terraform.tfvars (git-ignored)
cat > terraform.tfvars <<'EOF'
ssh_key = "ssh-ed25519 AAAA... you@example.com"
users   = "users.ldif"

# If the defaults are taken globally, override:
# s3_bucket_build         = "pcs-gpu-build-<your-name>"
# s3_bucket_benchmarking  = "pcs-gpu-benchmarking-<your-name>"

# If the login node type is out of capacity in your AZ, pick something else:
# instance_login = "c6i.4xlarge"
EOF

# 2. Create users.ldif (git-ignored). One entry per user.
#    See "Adding users" below for the format.

# 3. Deploy
terraform init
terraform apply
```

First apply takes ~60 minutes:

- VPC, S3, IAM, SGs: <2 min
- FSx OpenZFS: ~15 min
- FSx Lustre + DRA: ~20 min
- Image Builder AMI bake: ~35 min (dominates)
- PCS cluster and compute node groups: ~10 min

When it finishes, outputs include the PCS console URL. The login node
public IP is not in outputs yet — fetch it with:

```sh
aws ec2 describe-instances --region "$(terraform output -raw region 2>/dev/null || echo us-west-2)" \
  --filters "Name=tag:aws:pcs:cluster-id,Values=$(terraform output -raw pcs_cluster_id)" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[?!contains(keys(@),`Platform`)].[InstanceId,InstanceType,PublicIpAddress]' \
  --output table
```

The login node will be the smaller instance with a public IP; compute nodes
have private IPs only.

Then SSH in as your LDAP user:

```sh
ssh <your-uid>@<public-ip>
```

## Running a GPU benchmark

A minimal end-to-end workflow is provided in `benchmarks/g6e/`:

- `bench.py` — PyTorch matmul sweep across sizes and dtypes, writes CSV
- `capture.sh` — runs `bench.py` while sampling GPU counters with `dcgmi dmon`
- `job.sbatch` — Slurm wrapper that targets the `g6e` partition
- `plot.py` — reads results on your laptop and renders a TFLOPS chart and
  GPU utilisation / power / temperature timeseries

See [`benchmarks/g6e/README.md`](benchmarks/g6e/README.md) for the full
workflow.

## Configuration

All variables are declared in `variables.tf`. The most commonly-overridden
ones:

| Variable | Default | Purpose |
|---|---|---|
| `region`, `availability_zone` | `us-west-2`, `us-west-2c` | Where to deploy. The cluster is single-AZ. |
| `ssh_key` | none (required) | OpenSSH public key string (contents of `~/.ssh/id_*.pub`). |
| `users` | none (required) | Path to a user LDIF file, relative to the module root. |
| `instance_login` | `c6a.8xlarge` | Login node type. Change if the AZ is out of capacity. |
| `instance_gpu` | `[g7e.12xlarge, g6e.2xlarge]` | GPU types that each become their own queue. |
| `purchase_options` | spot for g7e, ondemand for g6e | Per-type purchase option. |
| `max_instances_per_queue` | 2 each | Per-type node cap. Cluster overall is PCS `SMALL` (32 node ceiling). |
| `capacity_block` | `{}` | Per-type ML Capacity Block reservation IDs, for types using `CAPACITY_BLOCK`. |
| `s3_bucket_build`, `s3_bucket_benchmarking` | `drmahes-pcs-gpu-*` | Must be globally unique. Change for your account. |

## Adding users

Users authenticate via LDAP. Edit `users.ldif` **before** the first
`terraform apply` to add yourself and anyone else who needs access. One
entry per user:

```ldif
dn: cn=alice,ou=people,dc=my-domain,dc=com
givenName: Alice
sn: Example
cn: alice
uid: alice
uidNumber: 2001
gidNumber: 2000
homeDirectory: /home/alice
loginShell: /bin/bash
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: top
objectClass: ldapPublicKey
mail: alice@example.com
sshPublicKey: ssh-ed25519 AAAA... alice@laptop
```

Give `uidNumber` values starting at 2000, unique per user.

To grant sudo, append them to the `wheel` group in the same LDIF:

```ldif
dn: cn=wheel,ou=groups,dc=my-domain,dc=com
changetype: modify
add: memberUid
memberUid: alice
```

Make sure the LDIF file you reference exists at the path you set in
`terraform.tfvars` as `users = "..."`. Mismatched paths fail at plan
time with "no such file".

To add a user **after** the cluster is deployed, edit `users.ldif` and
`terraform apply` — this replaces the LDAP instance, which runs the
user-data script again with the fresh LDIF. Takes ~3-5 min and does not
affect compute nodes or running jobs.

## Teardown

```sh
terraform destroy
```

Known failure: the LDAP Secrets Manager secret may not destroy cleanly.
If it complains:

```sh
aws secretsmanager delete-secret \
  --region us-west-2 \
  --secret-id ldap_password \
  --force-delete-without-recovery
```

## Known limitations

These are things that have bitten during development. Documented here so
they don't surprise you.

### 1. AMI rebakes require manual queue deletion

Any change to `modules/ami/pcs-component.yaml` or `cwa-config.json` rolls
a new immutable Image Builder version and forces an AMI rebake. Because
AWS Cloud Control API does not correctly order PCS queue-vs-node-group
destruction, `terraform apply` fails mid-way with:

```
AWS PCS can't delete the compute node group you specified because the
cluster has associated queues.
```

Workaround before `terraform apply`:

```sh
aws pcs list-queues --region us-west-2 --cluster-identifier <cluster-id> \
  --query 'queues[].[name,id]' --output text

# For each queue-id returned:
aws pcs delete-queue --region us-west-2 --cluster-identifier <cluster-id> \
  --queue-identifier <queue-id>

# Remove stale state entries:
terraform state rm 'module.pcs.awscc_pcs_queue.gpu["<instance-type>"]'

terraform apply
```

This is a known `hashicorp/awscc` provider limitation, not a bug in this
module. It goes away when the `aws` provider adds native PCS support.

### 2. Image Builder pipeline orphan after bake failure

If a bake fails mid-apply, the Image Builder pipeline can be left as an
orphan referencing the recipe. The next `terraform apply` then fails with:

```
ResourceDependencyException: Resource dependency error
```

Workaround:

```sh
aws imagebuilder list-image-pipelines --region us-west-2 \
  --query 'imagePipelineList[].arn' --output text

aws imagebuilder delete-image-pipeline --region us-west-2 \
  --image-pipeline-arn <pipeline-arn>
```

Then `terraform apply`.

### 3. Availability zone can run out of instance types

PCS retries RunInstances every ~3 minutes when the AZ is temporarily
out of the requested type. You will see it in CloudTrail as
`Server.InsufficientInstanceCapacity`. Options:

- Wait (capacity usually returns within an hour)
- Change `instance_login` or `instance_gpu` to a different family (Intel
  and AMD are independent pools)
- Destroy and redeploy in a different AZ

## Cost (rough)

Idle cluster (login node running, zero GPU jobs):

| Component | Est. $/day |
|---|---|
| PCS controller | ~$15 |
| Login node (c6a.4xlarge on-demand) | ~$15 |
| LDAP t3.micro | ~$0.25 |
| NAT Gateway + EIP | ~$1.50 |
| FSx OpenZFS (256 GiB SINGLE_AZ_1) | ~$2 |
| FSx Lustre (2400 GiB PERSISTENT_2, 125 MB/s/TiB) | ~$5 |
| **Total idle** | **~$40/day** |

GPU runtime costs on top, only while jobs are running. `min=0` on GPU
node groups means you pay zero GPU while idle. `g6e.2xlarge` on-demand is
~$2.24/hr; `g7e.12xlarge` on spot is ~$3-4/hr.

## Repo layout

```
main.tf                   # top-level module wiring
variables.tf              # top-level variables (tfvars override these)
terraform.tfvars          # your values (git-ignored)
users.ldif                # LDAP seed (git-ignored)
modules/
  vpc/                    # VPC, subnets, SGs, NAT
  iam/                    # Compute node IAM role and instance profile
  s3/                     # Reusable bucket module (instantiated twice)
  fsx/                    # OpenZFS, Lustre, DRA
  ldap/                   # OpenLDAP server
  ami/                    # Image Builder component, recipe, pipeline
  pcs/                    # Cluster, node groups, queues, launch templates
benchmarks/
  g6e/                    # Sample single-GPU benchmark + plotter
docs/
  ssh-troubleshooting.md  # Diagnostics for SSH failures
```

## Tags and SpringClean

Every Terraform-managed resource that supports tagging gets the following
applied via `default_tags` on the `aws` provider (see `providers.tf`):

| Tag | Value |
|---|---|
| `auto-delete` | `no` |
| `Project` | `pcs-gpu-benchmarking` |
| `Owner` | `drmahes` |

The PCS resources (`awscc_pcs_*`) don't honour `default_tags`, so they
explicitly set the same tag map themselves via `var.tags` on the pcs
module.

The benchmarking S3 bucket isn't managed by Terraform, so tag it once
manually after creating it:

```sh
aws s3api put-bucket-tagging --bucket "$BUCKET" \
  --tagging 'TagSet=[{Key=auto-delete,Value=no},{Key=Project,Value=pcs-gpu-benchmarking},{Key=Owner,Value=drmahes}]'
```

To customise tags for your project, edit the `local.common_tags` map at
the top of `providers.tf`.

## Contributing back

If you fix any of the Known Limitations properly (especially #1 and #3),
consider upstreaming the fix to
[aws-samples/sample-parallel-computing-service][upstream].
