# Requirements Document

## Introduction

This specification defines the requirements for automating the migration of EC2-based AWS Storage Gateways from Amazon Linux 2 (AL2) to Amazon Linux 2023 (AL2023). The migration follows AWS's recommended "Method 1" approach which preserves the gateway identity, file shares, and cached data.

## Glossary

- **Storage_Gateway**: AWS Storage Gateway service that provides hybrid cloud storage
- **AL2**: Amazon Linux 2 operating system (end of standard support June 2025)
- **AL2023**: Amazon Linux 2023 operating system (current supported version)
- **Migration_Tool**: The Terraform-based automation that orchestrates the migration process
- **Cache_Volume**: EBS volume attached to the gateway for local caching of S3 data
- **Gateway_ID**: Unique identifier for a Storage Gateway (format: sgw-XXXXXXXX)
- **CachePercentDirty**: CloudWatch metric indicating percentage of cache data not yet uploaded to S3

## Requirements

### Requirement 1: Pre-flight Validation

**User Story:** As an infrastructure operator, I want the migration tool to validate prerequisites before starting, so that I can avoid failed migrations and data loss.

#### Acceptance Criteria

1. WHEN the migration is initiated, THE Migration_Tool SHALL verify the old EC2 instance is in "stopped" state
2. WHEN the old instance is not stopped, THE Migration_Tool SHALL fail with a descriptive error message
3. THE Migration_Tool SHALL validate that all provided resource IDs (gateway_id, instance_id, volume_ids) match expected formats
4. WHEN invalid resource IDs are provided, THE Migration_Tool SHALL reject the configuration during terraform plan

### Requirement 2: Pre-migration Backup

**User Story:** As an infrastructure operator, I want automatic EBS snapshots created before migration, so that I can rollback if the migration fails.

#### Acceptance Criteria

1. WHEN create_snapshots is enabled, THE Migration_Tool SHALL create EBS snapshots of all cache volumes before migration
2. THE Migration_Tool SHALL tag snapshots with gateway ID, migration timestamp, and "pre-migration-backup" identifier
3. WHERE create_snapshots is disabled, THE Migration_Tool SHALL skip snapshot creation and proceed with migration

### Requirement 3: New Instance Provisioning

**User Story:** As an infrastructure operator, I want a new AL2023 gateway instance provisioned with the same network configuration, so that the migration is seamless to clients.

#### Acceptance Criteria

1. THE Migration_Tool SHALL use the existing ec2-sgw module to provision the new AL2023 instance
2. THE ec2-sgw module SHALL support a `migration_mode` variable that skips cache volume creation
3. THE Migration_Tool SHALL configure the new instance in the same subnet, availability zone, and security groups as the old instance
4. THE Migration_Tool SHALL apply IMDSv2 (http_tokens = required) for enhanced security
5. THE Migration_Tool SHALL encrypt the root volume using gp3 storage type
6. WHERE upgrade_instance_family is enabled, THE Migration_Tool SHALL upgrade instance types (M5→M7i, R5→R7i)
7. WHERE upgrade_instance_family is disabled, THE Migration_Tool SHALL use the same instance type as the old gateway
8. THE ec2-sgw module SHALL support optional EIP creation (migration may not need new EIP)

### Requirement 4: Cache Volume Migration

**User Story:** As an infrastructure operator, I want existing cache volumes attached to the new instance, so that cached data is preserved and clients don't experience cache misses.

#### Acceptance Criteria

1. THE Migration_Tool SHALL detach cache volumes from the old instance (implicit when instance is stopped)
2. THE Migration_Tool SHALL attach all specified cache volumes to the new AL2023 instance
3. THE Migration_Tool SHALL assign sequential device names (/dev/sdb, /dev/sdc, etc.) to attached volumes
4. WHEN volume attachment fails, THE Migration_Tool SHALL report the error with volume ID and reason

### Requirement 5: Migration Command Execution via SSM

**User Story:** As an infrastructure operator, I want the migration command executed automatically via SSM Run Command, so that I don't need manual SSH access to complete the migration.

#### Acceptance Criteria

1. THE Migration_Tool SHALL use AWS Systems Manager Run Command to execute the migration API call
2. THE Migration_Tool SHALL create an SSM document defining the migration command
3. THE Migration_Tool SHALL pass the gateway_id to the migration endpoint
4. WHEN the migration command fails, THE Migration_Tool SHALL capture and report the error from SSM
5. THE Migration_Tool SHALL support configurable timeout for the migration command (default: 600 seconds)
6. THE Migration_Tool SHALL require the EC2 instance to have SSM agent installed and IAM permissions

### Requirement 6: Post-migration Verification

**User Story:** As an infrastructure operator, I want automated verification that the migration succeeded, so that I have confidence before decommissioning the old instance.

#### Acceptance Criteria

1. WHEN migration completes, THE Migration_Tool SHALL verify the gateway status is "RUNNING"
2. THE Migration_Tool SHALL output the new instance ID, private IP, and migration summary
3. THE Migration_Tool SHALL provide clear next steps for DNS updates and old instance cleanup

### Requirement 7: Rollback Support

**User Story:** As an infrastructure operator, I want clear rollback procedures, so that I can recover if the migration fails.

#### Acceptance Criteria

1. THE Migration_Tool SHALL document rollback steps in outputs when migration fails
2. IF snapshots were created, THE Migration_Tool SHALL reference snapshot IDs in rollback instructions
3. THE Migration_Tool SHALL NOT automatically terminate the old instance

### Requirement 8: SSM Prerequisites and IAM

**User Story:** As an infrastructure operator, I want clear IAM requirements for SSM execution, so that I can configure permissions correctly.

#### Acceptance Criteria

1. THE Migration_Tool SHALL document required IAM permissions for SSM Run Command
2. THE Migration_Tool SHALL optionally create an IAM instance profile with SSM permissions
3. WHERE an existing instance profile is provided, THE Migration_Tool SHALL use it instead of creating a new one
4. THE Migration_Tool SHALL verify SSM agent connectivity before executing migration command

### Requirement 9: ec2-sgw Module Enhancements

**User Story:** As a module maintainer, I want the ec2-sgw module to support migration scenarios, so that migration examples can reuse existing module code.

#### Acceptance Criteria

1. THE ec2-sgw module SHALL add a `create_cache_volume` variable (default: true)
2. WHEN create_cache_volume is false, THE ec2-sgw module SHALL skip aws_ebs_volume and aws_volume_attachment resources
3. THE ec2-sgw module SHALL add a `create_eip` variable (default: true)
4. WHEN create_eip is false, THE ec2-sgw module SHALL skip aws_eip and aws_eip_association resources
5. THE ec2-sgw module SHALL add an `iam_instance_profile` variable to attach existing IAM profiles
6. THE ec2-sgw module SHALL output the instance_id for use by migration automation
