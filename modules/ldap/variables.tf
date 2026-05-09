variable "region" {
  type    = string
}

variable "ldap_instance" {
  description = "LDAP server instance type"
  type = string
  default = "t3.micro"
}

variable "ssh_key" {
  description = "SSH key pair to use for instances"
  type = string
}

variable "private_subnet_id" {
  description = "Private subnet ID"
  type = string
}

variable "private_sg_id" {
  description = "Private security group ID"
  type = string
}

variable "s3_bucket" {
  description = "S3 bucket name"
  type = string
}

variable "users_ldif" {
  description = "The users LDIF file"
  type = string
}
