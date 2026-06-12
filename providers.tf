provider "awscc" {
  region  = var.region
  profile = var.profile
}

provider "aws" {
  region  = var.region
  profile = var.profile
  default_tags {
    tags = {
      project     = "m3dc1-benchmark"
      auto-delete = "no"
    }
  }
}

