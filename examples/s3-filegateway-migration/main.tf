################################################################################
# S3 File Gateway Migration Example - Method 1
# Migrates an existing AL2 gateway to AL2023 while preserving cache disks
################################################################################

################################################################################
# Data Sources - Gather information about existing gateway
################################################################################

# Get current AWS region and account
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Get EC2 instance ID from Storage Gateway using external script
data "external" "gateway_instance" {
  program = ["bash", "${path.module}/get-gateway-instance.sh"]

  query = {
    gateway_id = var.gateway_id
    aws_region = data.aws_region.current.name
  }
}

# Get details of the old gateway instance
data "aws_instance" "old_sgw" {
  instance_id = data.external.gateway_instance.result.instance_id
}

# Get subnet details to extract VPC ID
data "aws_subnet" "old_sgw_subnet" {
  id = data.aws_instance.old_sgw.subnet_id
}

locals {
  # Use provided instance type or fall back to old instance type
  new_instance_type = var.instance_type != null ? var.instance_type : data.aws_instance.old_sgw.instance_type

  # Extract VPC ID from the subnet
  vpc_id = data.aws_subnet.old_sgw_subnet.vpc_id

  # Extract root disk configuration from old instance (convert set to list)
  old_root_disk = tolist(data.aws_instance.old_sgw.root_block_device)[0]

  # Build root_block_device config matching old instance
  root_block_device = {
    disk_size   = try(var.root_block_device.disk_size, local.old_root_disk.volume_size)
    volume_type = try(var.root_block_device.volume_type, local.old_root_disk.volume_type)
    kms_key_id  = try(var.root_block_device.kms_key_id, local.old_root_disk.kms_key_id != "" ? local.old_root_disk.kms_key_id : null)
  }
}

data "aws_ebs_volumes" "cache_volumes" {
  filter {
    name   = "attachment.instance-id"
    values = [data.aws_instance.old_sgw.id]
  }

  filter {
    name   = "attachment.device"
    values = ["/dev/sdb", "/dev/sdc", "/dev/sdd", "/dev/sde", "/dev/sdf", "/dev/sdg", "/dev/sdh", "/dev/sdi"]
  }
}

################################################################################
# New AL2023 Storage Gateway Instance
################################################################################

module "new_sgw" {
  source = "../../modules/ec2-sgw"

  name              = "${var.gateway_id}-al2023"
  gateway_type      = var.gateway_type
  subnet_id         = data.aws_instance.old_sgw.subnet_id
  vpc_id            = local.vpc_id
  availability_zone = data.aws_instance.old_sgw.availability_zone
  instance_type     = local.new_instance_type
  ssh_key_name      = data.aws_instance.old_sgw.key_name

  # Migration-specific settings - don't create new cache volume or EIP
  create_cache_volume = false
  create_eip          = false

  # Use existing security group from old instance
  create_security_group = false
  security_group_id     = tolist(data.aws_instance.old_sgw.vpc_security_group_ids)[0]

  # Preserve root block device settings from old instance
  root_block_device = local.root_block_device
}

