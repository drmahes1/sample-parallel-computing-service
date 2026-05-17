variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "private_subnet_id" {
  type = string
}

variable "public_cidr" {
  type = string
}

variable "private_cidr" {
  type = string
}

variable "s3_bucket_benchmarking" {
  description = "S3 bucket to link to FSx Lustre /results subdir via a bidirectional DRA."
  type        = string
}
