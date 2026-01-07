# Design Document

## Overview

This design describes the Terraform-based automation for migrating EC2 Storage Gateways from Amazon Linux 2 to AL2023. The solution follows AWS's "Method 1" migration approach and provides extensible scaffolding for different automation backends (SSM, Ansible, Lambda).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Migration Workflow                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │  Pre-flight  │───▶│   Backup     │───▶│  ec2-sgw     │       │
│  │  Validation  │    │  Snapshots   │    │  Module      │       │
│  └──────────────┘    └──────────────┘    │(migration    │       │
│                                          │ mode)        │       │
│                                          └──────────────┘       │
│                                                 │                │
│                                                 ▼                │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   Verify &   │◀───│   Execute    │◀───│   Attach     │       │
│  │   Output     │    │  Migration   │    │   Existing   │       │
│  └──────────────┘    └──────────────┘    │   Volumes    │       │
│                            │             └──────────────┘       │
│                            ▼                                     │
│              ┌─────────────────────────┐                        │
│              │   SSM Run Command       │                        │
│              │   (Migration Execution) │                        │
│              └─────────────────────────┘                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Module Changes Required

### ec2-sgw Module Enhancements

The existing `modules/ec2-sgw` module needs these additions to support migration:

```hcl
# New variables to add to modules/ec2-sgw/variables.tf

variable "create_cache_volume" {
  type        = bool
  description = "Create a new cache EBS volume. Set to false for migration scenarios."
  default     = true
}

variable "create_eip" {
  type        = bool
  description = "Create and associate an Elastic IP. Set to false for migration scenarios."
  default     = true
}

variable "iam_instance_profile" {
  type        = string
  description = "IAM instance profile name to attach. Required for SSM access."
  default     = null
}
```

```hcl
# Changes to modules/ec2-sgw/main.tf

resource "aws_ebs_volume" "cache_disk" {
  count = var.create_cache_volume ? 1 : 0  # Add count
  # ... existing config
}

resource "aws_volume_attachment" "ebs_volume" {
  count = var.create_cache_volume ? 1 : 0  # Add count
  # ... existing config
}

resource "aws_eip" "ip" {
  count  = var.create_eip ? 1 : 0  # Add count
  domain = "vpc"
}

resource "aws_eip_association" "eip_assoc" {
  count         = var.create_eip ? 1 : 0  # Add count
  instance_id   = aws_instance.ec2_sgw.id
  allocation_id = aws_eip.ip[0].id
}

resource "aws_instance" "ec2_sgw" {
  # ... existing config
  iam_instance_profile = var.iam_instance_profile  # Add this line
}
```

```hcl
# New output to add to modules/ec2-sgw/outputs.tf

output "instance_id" {
  value       = aws_instance.ec2_sgw.id
  description = "The EC2 instance ID of the Storage Gateway"
}
```

## File Structure

```
# Module changes
modules/ec2-sgw/
├── main.tf              # Add count to EBS/EIP resources, add iam_instance_profile
├── variables.tf         # Add create_cache_volume, create_eip, iam_instance_profile
└── outputs.tf           # Add instance_id output

# Migration example
examples/ec2-sgw-al2023-migration/
├── main.tf              # Uses ec2-sgw module with migration_mode settings
├── variables.tf         # Input variables with validation
├── outputs.tf           # Migration results and next steps
├── versions.tf          # Provider requirements
├── ssm.tf               # SSM document and execution
├── iam.tf               # IAM role/policy for SSM (optional)
├── terraform.tfvars.example
└── README.md
```

## Components and Interfaces

### Migration Example (main.tf)

Uses the ec2-sgw module with migration-specific settings:

```hcl
# Provision new AL2023 instance using ec2-sgw module
module "new_sgw" {
  source = "../../modules/ec2-sgw"

  name                  = "${var.gateway_id}-al2023-migrated"
  gateway_type          = var.gateway_type
  subnet_id             = data.aws_instance.old_sgw.subnet_id
  vpc_id                = var.vpc_id
  availability_zone     = data.aws_instance.old_sgw.availability_zone
  instance_type         = local.new_instance_type
  ssh_key_name          = data.aws_instance.old_sgw.key_name
  
  # Migration-specific settings
  create_cache_volume   = false  # Don't create new cache volume
  create_eip            = false  # Don't create new EIP
  iam_instance_profile  = var.iam_instance_profile
  
  # Use existing security group from old instance
  create_security_group = false
  security_group_id     = tolist(data.aws_instance.old_sgw.vpc_security_group_ids)[0]
}

# Attach existing cache volumes to new instance
resource "aws_volume_attachment" "cache" {
  for_each = toset(var.cache_volume_ids)

  device_name = "/dev/sd${substr("bcdefgh", index(var.cache_volume_ids, each.value), 1)}"
  volume_id   = each.value
  instance_id = module.new_sgw.instance_id

  force_detach = true
}
```

### SSM Execution (ssm.tf)

Uses AWS Systems Manager Run Command to execute the migration:

```hcl
resource "aws_ssm_document" "sgw_migrate" {
  name            = "SGW-AL2023-Migration-${var.gateway_id}"
  document_type   = "Command"
  document_format = "YAML"
  
  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Execute Storage Gateway AL2023 migration"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "executeMigration"
      inputs = {
        runCommand = [
          "#!/bin/bash",
          "set -e",
          "echo 'Waiting for gateway API to be ready...'",
          "for i in {1..30}; do curl -s http://localhost:8080/health && break || sleep 10; done",
          "echo 'Executing migration...'",
          "curl -X POST http://localhost:8080/migrate -d '{\"gatewayId\":\"${var.gateway_id}\"}'",
        ]
        timeoutSeconds = var.migration_timeout_seconds
      }
    }]
  })
}

resource "aws_ssm_association" "migrate" {
  name = aws_ssm_document.sgw_migrate.name
  
  targets {
    key    = "InstanceIds"
    values = [aws_instance.new_sgw.id]
  }
  
  depends_on = [aws_volume_attachment.cache]
}
```

### IAM for SSM (iam.tf - optional)

```hcl
resource "aws_iam_role" "sgw_ssm" {
  count = var.create_iam_role ? 1 : 0
  name  = "sgw-migration-ssm-${var.gateway_id}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  count      = var.create_iam_role ? 1 : 0
  role       = aws_iam_role.sgw_ssm[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "sgw_ssm" {
  count = var.create_iam_role ? 1 : 0
  name  = "sgw-migration-ssm-${var.gateway_id}"
  role  = aws_iam_role.sgw_ssm[0].name
}
```

## Data Models

### Migration Configuration

```hcl
# Required inputs
gateway_id       = "sgw-XXXXXXXX"      # Gateway to migrate
gateway_arn      = "arn:aws:..."       # Full gateway ARN
old_instance_id  = "i-xxxxxxxxx"       # Current AL2 instance
cache_volume_ids = ["vol-xxx", ...]    # Cache volumes to migrate

# Optional inputs
aws_region              = "us-east-1"
gateway_type            = "FILE_S3"    # FILE_S3, VTL, CACHED, STORED
upgrade_instance_family = true         # M5→M7i, R5→R7i
create_snapshots        = true         # Pre-migration backups
create_iam_role         = true         # Create IAM role for SSM
migration_timeout       = 600          # Seconds
```

### Migration State

```hcl
# Tracked in Terraform state
migration_state = {
  old_instance_id   = "i-old"
  new_instance_id   = "i-new"
  old_instance_type = "m5.xlarge"
  new_instance_type = "m7i.xlarge"
  cache_volumes     = ["vol-1", "vol-2"]
  snapshots         = ["snap-1", "snap-2"]
  status            = "provisioned"  # provisioned, migrating, completed, failed
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do.*

### Property 1: Instance State Validation
*For any* migration attempt, the old gateway instance must be in "stopped" state before any resources are created.
**Validates: Requirements 1.1, 1.2**

### Property 2: Resource ID Format Validation
*For any* provided gateway_id, instance_id, or volume_id, the format must match AWS resource ID patterns.
**Validates: Requirements 1.3, 1.4**

### Property 3: Snapshot Creation Consistency
*For any* migration with create_snapshots=true, the number of snapshots created must equal the number of cache volumes provided.
**Validates: Requirements 2.1, 2.2**

### Property 4: Network Configuration Preservation
*For any* new instance provisioned, the subnet_id, availability_zone, and security_group_ids must match the old instance.
**Validates: Requirements 3.2**

### Property 5: Volume Attachment Completeness
*For any* migration, all specified cache volumes must be attached to the new instance with unique device names.
**Validates: Requirements 4.2, 4.3**

### Property 6: Instance Type Upgrade Mapping
*For any* migration with upgrade_instance_family=true, M5 types must map to M7i and R5 types must map to R7i.
**Validates: Requirements 3.5**

## Error Handling

| Error Condition | Handling Strategy |
|-----------------|-------------------|
| Old instance not stopped | Fail with precondition error during plan |
| Invalid resource IDs | Fail validation during plan |
| Volume attachment failure | Report error, leave instance for manual recovery |
| Migration command timeout | Report timeout, provide manual execution steps |
| Gateway not responding | Retry with backoff, then fail with diagnostics |

## Testing Strategy

### Unit Tests
- Variable validation tests (invalid formats rejected)
- Instance type mapping tests (upgrade logic)
- Tag generation tests

### Integration Tests
- End-to-end migration with test gateway
- Rollback procedure verification
- Each automation backend (SSM, Ansible, Lambda)

### Property-Based Tests
- Resource ID format validation across random inputs
- Instance type mapping completeness
