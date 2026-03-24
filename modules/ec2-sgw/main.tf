##########################
## Create EC2 Instance ##
##########################

locals {
  # Map gateway types to SSM parameter paths (AL2023-based AMIs)
  gateway_type_ssm_paths = {
    "FILE_S3" = "/aws/service/storagegateway/ami/FILE_S3/latest"
    "VTL"     = "/aws/service/storagegateway/ami/VTL/latest"
    "CACHED"  = "/aws/service/storagegateway/ami/CACHED/latest"
    "STORED"  = "/aws/service/storagegateway/ami/STORED/latest"
  }
}

data "aws_ssm_parameter" "sgw_ami" {
  name = local.gateway_type_ssm_paths[var.gateway_type]
}

resource "aws_instance" "ec2_sgw" {
  #checkov:skip=CKV_AWS_126:Detailed monitoring is optional for Storage Gateway EC2 instances
  #checkov:skip=CKV2_AWS_41:IAM role attachment is optional - users can attach roles via instance profile variable if needed
  ami                    = data.aws_ssm_parameter.sgw_ami.value
  vpc_security_group_ids = var.create_security_group ? aws_security_group.ec2_sg[*].id : [var.security_group_id]
  subnet_id              = var.subnet_id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  ebs_optimized          = true
  availability_zone      = var.availability_zone

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_size = try(tonumber(var.root_block_device["disk_size"]), 80)
    volume_type = try(var.root_block_device["volume_type"], "gp3")
    kms_key_id  = try(var.root_block_device["kms_key_id"], null)
  }
  tags = {
    Name = var.name
  }

  lifecycle {
    # the Security group ID must be non-empty or create_security_group must be true
    precondition {
      condition     = var.create_security_group || try((length(var.security_group_id) > 3 && substr(var.security_group_id, 0, 3) == "sg-"), false)
      error_message = "Please specify create_security_group = true or provide a valid Security Group ID for var.security_group_id"
    }

    # Ignore AMI changes to prevent unexpected instance replacement
    # To update the AMI, use: terraform apply -replace="module.ec2_sgw.aws_instance.ec2_sgw"
    ignore_changes = [ami]
  }
}

resource "aws_eip" "ip" {
  count    = var.create_eip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.ec2_sgw.id
}

resource "aws_volume_attachment" "ebs_volume" {
  device_name = "/dev/sdb"
  volume_id   = aws_ebs_volume.cache_disk.id
  instance_id = aws_instance.ec2_sgw.id
}

resource "aws_ebs_volume" "cache_disk" {
  availability_zone = aws_instance.ec2_sgw.availability_zone
  encrypted         = true
  size              = try(tonumber(var.cache_block_device["disk_size"]), 150)
  type              = try(var.cache_block_device["volume_type"], "gp3")
  kms_key_id        = try(var.cache_block_device["kms_key_id"], null)
}