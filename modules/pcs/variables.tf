variable "region" {
  type = string
}

variable "public_subnet_id" {
  description = "Public subnet ID"
  type        = string
}

variable "public_sg_id" {
  description = "Public security group ID"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID"
  type        = string
}

variable "private_sg_ids" {
  description = "Private security group IDs"
  type        = list(string)
}

variable "ssh_key" {
  description = "SSH key pair to use for instances"
  type        = string
}

variable "slurm_version" {
  description = "Slurm version"
  type        = string
}

variable "pcs_compute_profile_arn" {
  description = "ARN of the PCS compute profile to attach to instances"
  type        = string
}

variable "ami_id_x86" {
  description = "The AMI ID of the PCS X86_64 instance"
  type        = string
}

variable "instance_login" {
  description = "Instance type of login node(s)"
  type        = string
}

variable "instance_gpu" {
  description = "Instance types to create as GPU compute node groups / queues."
  type        = list(string)
}

variable "purchase_options" {
  description = "Per-instance-type purchase option: ONDEMAND, SPOT, or CAPACITY_BLOCK."
  type        = map(string)
  default     = {}
}

variable "capacity_block" {
  description = "Per-instance-type ML Capacity Block reservation IDs. Only used when purchase_option is CAPACITY_BLOCK."
  type        = map(string)
  default     = {}
}

variable "max_instances_per_queue" {
  description = "Per-instance-type max compute node count. Missing entries default to 1."
  type        = map(number)
  default     = {}
}

variable "zfs_filesystem_dns" {
  description = "FSx Lustre filesystem DNS"
  type        = string
}

variable "zfs_filesystem_mnt" {
  description = "FSx Lustre filesystem mount point"
  type        = string
}

variable "lustre_filesystem_dns" {
  description = "FSx Lustre filesystem DNS"
  type        = string
}

variable "lustre_filesystem_mnt" {
  description = "FSx Lustre filesystem mount point"
  type        = string
}

variable "tags" {
  description = "Tags to add to infrastructure"
  type        = map(string)
  default     = {}
}
