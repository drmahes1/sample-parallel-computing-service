
variable "profile" {
  type        = string
  description = "The AWS profile used to deploy the clusters."
  default     = null
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "availability_zone" {
  type    = string
  default = "us-west-2c"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_cidr" {
  type    = string
  default = "10.0.0.0/24"
}

variable "private_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "slurm_version" {
  description = "Slurm version"
  type        = string
  default     = "25.05"
}

variable "instance_login" {
  description = "Instance type of login node(s)"
  type        = string
  default     = "c6a.8xlarge"
}

variable "instance_gpu" {
  description = "Instance types to create as GPU compute node groups / queues."
  type        = list(string)
  default = [
    "g7e.12xlarge",
    "g6e.2xlarge",
  ]
}

variable "purchase_options" {
  description = <<-EOT
    Per-instance-type purchase option. Keys are instance types from `instance_gpu`.
    Valid values: "ONDEMAND", "SPOT", "CAPACITY_BLOCK".
    Missing entries default to "ONDEMAND".
  EOT
  type        = map(string)
  default = {
    "g7e.12xlarge" = "SPOT"
    "g6e.2xlarge"  = "ONDEMAND"
  }
}

variable "capacity_block" {
  description = <<-EOT
    ML Capacity Block reservation IDs keyed by instance type. Only required
    for instance types with purchase_option = "CAPACITY_BLOCK". When no
    reservation is held, leave the key absent and the node group stays at
    min=0 without launching instances.
  EOT
  type        = map(string)
  default     = {}
}

variable "max_instances_per_queue" {
  description = "Per-instance-type max compute node count. Missing entries default to 1."
  type        = map(number)
  default = {
    "g7e.12xlarge" = 2
    "g6e.2xlarge"  = 2
  }
}

variable "ssh_key" {
  description = "ssh public key for instances"
  type        = string
  default     = null
}

variable "s3_bucket_build" {
  description = "S3 bucket used for build/staging artefacts (AMI Image Builder logs, pcs-component.yaml, LDAP seed)."
  type        = string
  default     = "drmahes-pcs-gpu-build"
}

variable "s3_bucket_benchmarking" {
  description = "S3 bucket linked to FSx Lustre at /fsx/results via a bidirectional Data Repository Association."
  type        = string
  default     = "drmahes-pcs-gpu-benchmarking"
}

variable "users" {
  description = "A LDIF file containing users of the cluster"
  type        = string
  default     = null
}
