
locals {
  zfs_security_group_rules = {
    ingress = {
      "sunrpc_tcp" = {
        from_port   = 111
        ip_protocol = "tcp"
        to_port     = 111
      }
      "sunrpc_udp" = {
        from_port   = 111
        ip_protocol = "udp"
        to_port     = 111
      }
      "nfsd_tcp" = {
        from_port   = 2049
        ip_protocol = "tcp"
        to_port     = 2049
      }
      "nfsd_udp" = {
        from_port   = 2049
        ip_protocol = "udp"
        to_port     = 2049
      }
      "high_tcp" = {
        from_port   = 20001
        ip_protocol = "tcp"
        to_port     = 20003
      }
      "high_udp" = {
        from_port   = 20001
        ip_protocol = "udp"
        to_port     = 20003
      }
    }
    egress = {
      "sunrpc_tcp" = {
        from_port   = 111
        ip_protocol = "tcp"
        to_port     = 111
      }
      "sunrpc_udp" = {
        from_port   = 111
        ip_protocol = "udp"
        to_port     = 111
      }
      "nfsd_tcp" = {
        from_port   = 2049
        ip_protocol = "tcp"
        to_port     = 2049
      }
      "nfsd_udp" = {
        from_port   = 2049
        ip_protocol = "udp"
        to_port     = 2049
      }
      "high_tcp" = {
        from_port   = 20001
        ip_protocol = "tcp"
        to_port     = 20003
      }
      "high_udp" = {
        from_port   = 20001
        ip_protocol = "udp"
        to_port     = 20003
      }
    }
  }
  fsxl_security_group_rules = {
    ingress = {
      "988" = {
        from_port   = 988
        ip_protocol = "tcp"
        to_port     = 988
      }
      "1018" = {
        from_port   = 1018
        ip_protocol = "tcp"
        to_port     = 1023
      }
    }
    egress = {
      "988" = {
        from_port   = 988
        ip_protocol = "tcp"
        to_port     = 988
      }
      "1018" = {
        from_port   = 1018
        ip_protocol = "tcp"
        to_port     = 1023
      }
    }
  }
}

resource "aws_security_group" "zfs" {
  name = "aws_zfs_security_group"
  vpc_id = var.vpc_id
  description = "Security group for Amazon FSx OpenZFS file system"
}

resource "aws_vpc_security_group_ingress_rule" "zfs_allow_ingress" {
  for_each = local.zfs_security_group_rules.ingress
  security_group_id = aws_security_group.zfs.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = each.value.from_port
  ip_protocol       = each.value.ip_protocol
  to_port           = each.value.to_port
  description = "Ingress rule for Amazon FSx OpenZFS"
}

resource "aws_vpc_security_group_egress_rule" "zfs_allow_egress" {
  for_each = local.zfs_security_group_rules.egress
  security_group_id = aws_security_group.zfs.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = each.value.from_port
  ip_protocol       = each.value.ip_protocol
  to_port           = each.value.to_port
  description = "Egress rule for Amazon FSx OpenZFS"
}

resource "aws_fsx_openzfs_file_system" "fsxz" {
  storage_capacity    = 64
  subnet_ids          = [var.private_subnet_id]
  deployment_type     = "SINGLE_AZ_1"
  delete_options      = ["DELETE_CHILD_VOLUMES_AND_SNAPSHOTS"]
  throughput_capacity = 64
  security_group_ids = [aws_security_group.zfs.id]

  # Ensure security group rules are created before the file system
  depends_on = [
    aws_vpc_security_group_ingress_rule.zfs_allow_ingress,
    aws_vpc_security_group_egress_rule.zfs_allow_egress
  ]

  root_volume_configuration {
    data_compression_type = "ZSTD"
    nfs_exports {
      client_configurations {
        clients = var.vpc_cidr
        options = ["sync", "crossmnt", "no_root_squash"]
      }
    }
  }
}

resource "aws_fsx_openzfs_volume" "sw" {
  name = "sw"
  parent_volume_id = aws_fsx_openzfs_file_system.fsxz.root_volume_id
  data_compression_type = "ZSTD"
  nfs_exports {
    client_configurations {
      clients = var.vpc_cidr
      options = ["sync", "crossmnt", "no_root_squash", "rw"]
    }
  }
}

resource "aws_fsx_openzfs_volume" "home" {
  name = "home"
  parent_volume_id = aws_fsx_openzfs_file_system.fsxz.root_volume_id
  data_compression_type = "ZSTD"
  nfs_exports {
    client_configurations {
      clients = var.vpc_cidr
      options = ["sync", "crossmnt", "no_root_squash", "rw"]
    }
  }
}

resource "aws_security_group" "fsxl" {
  name = "aws_fsx_lustre_security_group"
  vpc_id = var.vpc_id
  description = "Security group for Amazon FSx Lustre file system"
}

resource "aws_vpc_security_group_ingress_rule" "fsxl_allow_ingress" {
  for_each = local.fsxl_security_group_rules.ingress
  security_group_id = aws_security_group.fsxl.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = each.value.from_port
  ip_protocol       = each.value.ip_protocol
  to_port           = each.value.to_port
  description = "Ingress rule for Amazon FSx Lustre"
}

resource "aws_vpc_security_group_ingress_rule" "fsxl_allow_ingress_efa" {
  security_group_id = aws_security_group.fsxl.id
  ip_protocol       = -1
  referenced_security_group_id  = aws_security_group.fsxl.id
  description = "Ingress rule for Amazon FSx Lustre"
}

resource "aws_vpc_security_group_egress_rule" "fsxl_allow_egress" {
  for_each = local.fsxl_security_group_rules.egress
  security_group_id = aws_security_group.fsxl.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = each.value.from_port
  ip_protocol       = each.value.ip_protocol
  to_port           = each.value.to_port
  description = "Egress rule for Amazon FSx Lustre"
}

resource "aws_vpc_security_group_egress_rule" "fsxl_allow_egress_efa" {
  security_group_id = aws_security_group.fsxl.id
  ip_protocol       = -1
  referenced_security_group_id  = aws_security_group.fsxl.id
  description = "Egress rule for Amazon FSx Lustre"
}

resource "aws_fsx_lustre_file_system" "fsxl" {
  deployment_type = "PERSISTENT_2"
  data_compression_type = "LZ4"
  efa_enabled = true
  security_group_ids = [aws_security_group.fsxl.id]
  storage_type = "SSD"
  storage_capacity = 4800
  subnet_ids = [var.private_subnet_id]
  per_unit_storage_throughput = 1000

  metadata_configuration {
    mode = "AUTOMATIC"
  }
}

resource "aws_fsx_data_repository_association" "lustre_s3" {
  file_system_id       = aws_fsx_lustre_file_system.fsxl.id
  file_system_path     = "/data"
  data_repository_path = "s3://satheesh-ohio-hpc-bucket"

  s3 {
    auto_export_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }
    auto_import_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }
  }
}

