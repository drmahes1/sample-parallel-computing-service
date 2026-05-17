variable "region" {
  type    = string
}

variable "x86_build_instance" {
  description = "X86 build instance type"
  type = string
  default = "c7a.16xlarge"
}

variable "arm_build_instance" {
  description = "ARM build instance type"
  type = string
  default = "c7g.4xlarge"
}

variable "s3_bucket" {
  description = "S3 bucket that contains the install components"
  type = string
}

variable "image_receipe_version" {
  description = <<-EOT
    Base image recipe version. The real version applied to the Image Builder
    recipe is suffixed with a hash of pcs-component.yaml + cwa-config.json so
    each edit rolls an immutable new recipe version automatically.
  EOT
  type    = string
  default = "1.0"
}

variable "dlami_base_name_prefix" {
  description = <<-EOT
    DLAMI family name prefix used in the aws_ami data lookup. Defaults to the
    multi-CUDA "Base OSS" AL2023 family, which supports G4dn, G5, G6, Gr6, G6e,
    G7e, P4d, P4de, P5, P5e, P5en, P6-B200, P6-B300 and ships multiple CUDA
    toolkits plus DCGM, aws-ofi-nccl, NVIDIA Container Toolkit.
  EOT
  type    = string
  default = "Deep Learning Base OSS Nvidia Driver GPU AMI (Amazon Linux 2023)"
}

variable "dlami_release_date" {
  description = <<-EOT
    DLAMI release date (YYYYMMDD) to pin. Bump this when you want to move to a
    newer driver/CUDA/DCGM release. The 20260121 release was the first AL2023
    Base OSS to list g7e in supported_ec2_instances.
  EOT
  type    = string
  default = "20260121"
}

variable "ssh_key" {
  description = "SSH key pair to use for instances"
  type = string
}

variable "public_subnet_id" {
  description = "Public subnet ID"
  type = string
}

variable "public_sg_id" {
  description = "Public security group ID"
  type = string
}

variable "slurm_version" {
  description = "Slurm version"
  type = string
}

variable "zfs_filesystem_dns" {
  description = "FSx Lustre filesystem DNS"
  type        = string
}

variable "zfs_filesystem_mnt" {
  description = "FSx Lustre filesystem mount point"
  type        = string
}

variable "ldap_dns" {
  description = "Private DNS address of LDAP server"
  type        = string
}

variable "ldap_password" {
  description = "LDAP bind password"
  type        = string
}
