resource "awscc_pcs_cluster" "wx" {
  name = "wx-cluster"

  networking = {
    subnet_ids         = [var.public_subnet_id]
    security_group_ids = [var.public_sg_id]
  }

  scheduler = {
    type    = "SLURM"
    version = var.slurm_version
  }

  size = "SMALL"

  tags = var.tags
}

# --- Login node -------------------------------------------------------------

locals {
  login_instance_template = (
    fileexists("${path.module}/templates/${var.instance_login}.userdata.tpl") ?
    "${path.module}/templates/${var.instance_login}.userdata.tpl" :
    "${path.module}/templates/default.userdata.tpl"
  )
}

resource "aws_launch_template" "pcs_login" {
  name = "login-wx"

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
  }

  key_name = var.ssh_key

  iam_instance_profile {
    arn = var.pcs_compute_profile_arn
  }
  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = true
    device_index                = 0
    network_card_index          = 0
    security_groups = [
      var.public_sg_id
    ]
  }

  user_data = base64encode(templatefile(local.login_instance_template, {
    zfs_dns    = var.zfs_filesystem_dns
    zfs_mnt    = var.zfs_filesystem_mnt
    lustre_dns = var.lustre_filesystem_dns
    lustre_mnt = var.lustre_filesystem_mnt
  }))
}

resource "awscc_pcs_compute_node_group" "login" {
  name       = "login"
  cluster_id = awscc_pcs_cluster.wx.name
  custom_launch_template = {
    template_id = aws_launch_template.pcs_login.id
    version     = aws_launch_template.pcs_login.latest_version
  }
  iam_instance_profile_arn = var.pcs_compute_profile_arn
  ami_id                   = var.ami_id_x86
  instance_configs = [
    {
      instance_type = var.instance_login
    }
  ]
  scaling_configuration = {
    min_instance_count = 1,
    max_instance_count = 1
  }
  subnet_ids      = [var.public_subnet_id]
  purchase_option = "ONDEMAND"

  tags = var.tags

  lifecycle {
    # Suppress awscc spurious drift:
    # - cluster_id round-trips between short ID and cluster name
    # - slurm_configuration / spot_options inferred by API after creation
    #   but read back as new on every plan
    ignore_changes = [
      cluster_id,
      slurm_configuration,
      spot_options,
    ]
  }
}

# --- GPU compute node groups -----------------------------------------------

resource "aws_placement_group" "pcs" {
  name     = "pcs-wx"
  strategy = "cluster"
}

locals {
  all_instances = toset(concat(var.instance_gpu))
  nics = { for instance in local.all_instances :
  instance => range(0, data.aws_ec2_instance_type.all[instance].maximum_network_cards) }
  cores = { for instance in local.all_instances :
  instance => data.aws_ec2_instance_type.all[instance].default_cores }

  # Whether this instance type supports EFA. Drives the network_interfaces
  # interface_type in the launch template. g6e.2xlarge (and similar small
  # sizes) don't support EFA and need a plain ENA interface.
  efa_supported = { for instance in local.all_instances :
    instance => data.aws_ec2_instance_type.all[instance].efa_supported
  }

  # Fall back to ONDEMAND if a purchase option isn't specified for a type.
  effective_purchase = { for i in var.instance_gpu :
    i => upper(lookup(var.purchase_options, i, "ONDEMAND"))
  }

  # Per-instance-type launch-template userdata file, with fallback to default.
  userdata_template = { for i in var.instance_gpu :
    i => (
      fileexists("${path.module}/templates/${i}.userdata.tpl") ?
      "${path.module}/templates/${i}.userdata.tpl" :
      "${path.module}/templates/default.userdata.tpl"
    )
  }
}

data "aws_ec2_instance_type" "all" {
  for_each      = local.all_instances
  instance_type = each.value
}

resource "aws_launch_template" "pcs" {
  for_each = local.all_instances
  name     = "pcs-${each.value}"

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
  }

  key_name = var.ssh_key

  # hpc* types don't accept cpu_options; existing GPU types are fine.
  dynamic "cpu_options" {
    for_each = startswith(each.value, "hpc") ? [] : [each.value]
    content {
      core_count       = local.cores[each.value]
      threads_per_core = 1
    }
  }

  iam_instance_profile {
    arn = var.pcs_compute_profile_arn
  }

  # Only emit capacity-block market options when the type uses CAPACITY_BLOCK
  # AND a reservation ID has actually been supplied. This keeps queues valid
  # (and the apply working) when we don't currently hold a reservation.
  dynamic "instance_market_options" {
    for_each = (
      local.effective_purchase[each.value] == "CAPACITY_BLOCK"
      && lookup(var.capacity_block, each.value, null) != null
    ) ? [1] : []
    content {
      market_type = "capacity-block"
    }
  }

  dynamic "capacity_reservation_specification" {
    for_each = (
      local.effective_purchase[each.value] == "CAPACITY_BLOCK"
      && lookup(var.capacity_block, each.value, null) != null
    ) ? [1] : []
    content {
      capacity_reservation_target {
        capacity_reservation_id = var.capacity_block[each.value]
      }
    }
  }

  monitoring {
    enabled = true
  }
  placement {
    group_id = aws_placement_group.pcs.placement_group_id
  }
  dynamic "network_interfaces" {
    for_each = local.nics[each.value]
    iterator = nic
    content {
      associate_public_ip_address = false
      device_index                = tonumber(nic.value) >= 1 ? "1" : "0"
      network_card_index          = tonumber(nic.value)
      interface_type              = local.efa_supported[each.value] ? "efa" : null
      security_groups             = var.private_sg_ids
    }
  }

  user_data = base64encode(templatefile(local.userdata_template[each.value], {
    zfs_dns    = var.zfs_filesystem_dns
    zfs_mnt    = var.zfs_filesystem_mnt
    lustre_dns = var.lustre_filesystem_dns
    lustre_mnt = var.lustre_filesystem_mnt
  }))
}

resource "awscc_pcs_compute_node_group" "gpu" {
  for_each   = toset(var.instance_gpu)
  name       = replace(split(".", each.value)[0], "-", "_")
  cluster_id = awscc_pcs_cluster.wx.name
  custom_launch_template = {
    template_id = aws_launch_template.pcs[each.value].id
    version     = aws_launch_template.pcs[each.value].latest_version
  }
  iam_instance_profile_arn = var.pcs_compute_profile_arn
  ami_id                   = var.ami_id_x86
  instance_configs = [
    {
      instance_type = each.value
    }
  ]

  # min=0 so idle GPU types cost nothing; max per-type comes from the map.
  scaling_configuration = {
    min_instance_count = 0,
    max_instance_count = lookup(var.max_instances_per_queue, each.value, 1)
  }
  subnet_ids      = [var.private_subnet_id]
  purchase_option = local.effective_purchase[each.value]

  tags = var.tags

  lifecycle {
    # Same awscc spurious drift suppression as login node group above.
    ignore_changes = [
      cluster_id,
      slurm_configuration,
      spot_options,
    ]
  }
}

# One queue per instance type (e.g. p5e, g7e, g6e). Queue names use
# split(".", type)[0] with '-' replaced by '_' so families like p6-b200
# would map to p6_b200.
resource "awscc_pcs_queue" "gpu" {
  for_each   = toset(var.instance_gpu)
  cluster_id = awscc_pcs_cluster.wx.cluster_id
  name       = replace(split(".", each.value)[0], "-", "_")
  compute_node_group_configurations = [
    { compute_node_group_id = awscc_pcs_compute_node_group.gpu[each.value].compute_node_group_id }
  ]

  tags = var.tags

  depends_on = [awscc_pcs_cluster.wx]
}
