# Tags applied to every resource that supports tagging via the aws provider.
# Includes "auto-delete = no" so Isengard's SpringClean sweep does not delete
# infrastructure. The awscc provider does not honour default_tags, so PCS
# resources tag themselves explicitly via var.common_tags in modules/pcs.
locals {
  common_tags = {
    "auto-delete" = "no"
    "Project"     = "pcs-gpu-benchmarking"
    "Owner"       = "drmahes"
  }
}

provider "awscc" {
  region  = var.region
  profile = var.profile
}

provider "aws" {
  region  = var.region
  profile = var.profile

  default_tags {
    tags = local.common_tags
  }
}
