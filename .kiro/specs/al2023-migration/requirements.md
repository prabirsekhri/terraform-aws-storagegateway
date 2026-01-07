# Requirements Document

## Introduction

This specification defines the requirements for automating the migration of AWS Storage Gateways from Amazon Linux 2 (AL2) to Amazon Linux 2023 (AL2023). The migration supports both EC2-hosted and VMware-hosted gateways, following AWS's recommended "Method 1" approach which preserves the gateway identity, file shares, and cached data.

## Glossary

- **Storage_Gateway**: AWS Storage Gateway service that provides hybrid cloud storage
- **AL2**: Amazon Linux 2 operating system (end of standard support June 2025)
- **AL2023**: Amazon Linux 2023 operating system (current supported version)
- **Migration_Tool**: The Terraform-based automation that orchestrates the migration process
- **Cache_Volume**: EBS volume (EC2) or VMDK (VMware) attached to the gateway for local caching
- **Cache_Disk**: Generic term for cache storage on either platform
- **Gateway_ID**: Unique identifier for a Storage Gateway (format: sgw-XXXXXXXX)
- **CachePercentDirty**: CloudWatch metric indicating percentage of cache data not yet uploaded to S3
- **OVA**: Open Virtual Appliance format used for VMware gateway deployment

## Requirements

### Requirement 1: Pre-flight Validation

**User Story:** As an infrastructure operator, I want the migration tool to validate prerequisites before starting, so that I can avoid failed migrations and data loss.

#### Acceptance Criteria

1. THE Migration_Tool SHALL support a `platform` variable to specify "ec2" or "vmware"
2. WHEN platform is "ec2", THE Migration_Tool SHALL verify the old EC2 instance is in "stopped" state
3. WHEN platform is "vmware", THE Migration_Tool SHALL verify the old VM is powered off
4. WHEN the old gateway is not stopped/powered off, THE Migration_Tool SHALL fail with a descriptive error message
5. THE Migration_Tool SHALL validate that the gateway_id matches expected format (sgw-XXXXXXXX)
6. WHEN invalid resource IDs are provided, THE Migration_Tool SHALL reject the configuration during terraform plan

### Requirement 2: Pre-migration Backup

**User Story:** As an infrastructure operator, I want backups created before migration, so that I can rollback if the migration fails.

#### Acceptance Criteria

1. WHEN platform is "ec2" and create_snapshots is enabled, THE Migration_Tool SHALL create EBS snapshots of all cache volumes
2. WHEN platform is "vmware", THE Migration_Tool SHALL document VMware snapshot procedures (manual step)
3. THE Migration_Tool SHALL tag EC2 snapshots with gateway ID, migration timestamp, and "pre-migration-backup" identifier
4. WHERE create_snapshots is disabled, THE Migration_Tool SHALL skip snapshot creation and proceed with migration

### Requirement 3: New Gateway Provisioning (EC2)

**User Story:** As an infrastructure operator, I want a new AL2023 EC2 gateway instance provisioned with the same network configuration, so that the migration is seamless to clients.

#### Acceptance Criteria

1. WHEN platform is "ec2", THE Migration_Tool SHALL use the existing ec2-sgw module to provision the new AL2023 instance
2. THE ec2-sgw module SHALL support a `create_cache_volume` variable (default: true) that skips cache volume creation when false
3. THE Migration_Tool SHALL configure the new instance in the same subnet, availability zone, and security groups as the old instance
4. THE Migration_Tool SHALL apply IMDSv2 (http_tokens = required) for enhanced security
5. THE Migration_Tool SHALL encrypt the root volume using gp3 storage type
6. WHERE upgrade_instance_family is enabled, THE Migration_Tool SHALL upgrade instance types (M5→M7i, R5→R7i)
7. WHERE upgrade_instance_family is disabled, THE Migration_Tool SHALL use the same instance type as the old gateway
8. THE ec2-sgw module SHALL support optional EIP creation via `create_eip` variable (default: true)

### Requirement 4: New Gateway Provisioning (VMware)

**User Story:** As an infrastructure operator, I want a new AL2023 VMware gateway deployed, so that I can migrate my on-premises gateway.

#### Acceptance Criteria

1. WHEN platform is "vmware", THE Migration_Tool SHALL document the OVA deployment process
2. THE Migration_Tool SHALL provide the download URL for the AL2023 OVA from AWS
3. THE Migration_Tool SHALL document vSphere/ESXi deployment steps
4. THE Migration_Tool SHALL document network configuration to match the old gateway
5. THE Migration_Tool SHALL document cache disk attachment from the old VM to the new VM

### Requirement 5: Cache Disk Migration (EC2)

**User Story:** As an infrastructure operator, I want existing EBS cache volumes attached to the new EC2 instance, so that cached data is preserved.

#### Acceptance Criteria

1. WHEN platform is "ec2", THE Migration_Tool SHALL detach cache volumes from the old instance (implicit when stopped)
2. THE Migration_Tool SHALL attach all specified cache volumes to the new AL2023 instance
3. THE Migration_Tool SHALL assign sequential device names (/dev/sdb, /dev/sdc, etc.) to attached volumes
4. WHEN volume attachment fails, THE Migration_Tool SHALL report the error with volume ID and reason

### Requirement 6: Cache Disk Migration (VMware)

**User Story:** As an infrastructure operator, I want existing VMDK cache disks attached to the new VMware gateway, so that cached data is preserved.

#### Acceptance Criteria

1. WHEN platform is "vmware", THE Migration_Tool SHALL document the VMDK detachment process from old VM
2. THE Migration_Tool SHALL document the VMDK attachment process to new VM
3. THE Migration_Tool SHALL specify the correct SCSI controller and disk node configuration
4. THE Migration_Tool SHALL reference the disk_node variable format (e.g., "SCSI (0:1)")

### Requirement 7: Migration Command Execution via Ansible

**User Story:** As an infrastructure operator, I want the migration command executed automatically via Ansible, so that I have a unified approach for both EC2 and VMware gateways.

#### Acceptance Criteria

1. THE Migration_Tool SHALL use Ansible playbooks to execute the migration API call
2. THE Migration_Tool SHALL provide playbooks that work for both EC2 and VMware platforms
3. THE Migration_Tool SHALL wait for the gateway API to be ready before executing migration
4. THE Migration_Tool SHALL pass the gateway_id to the migration endpoint
5. WHEN the migration command fails, THE Migration_Tool SHALL capture and report the error from Ansible
6. THE Migration_Tool SHALL support configurable timeout for the migration command (default: 600 seconds)
7. WHEN platform is "ec2", THE Migration_Tool SHALL support connection via AWS SSM Session Manager plugin
8. WHEN platform is "vmware", THE Migration_Tool SHALL support connection via SSH

### Requirement 8: Post-migration Verification

**User Story:** As an infrastructure operator, I want automated verification that the migration succeeded, so that I have confidence before decommissioning the old gateway.

#### Acceptance Criteria

1. WHEN migration completes, THE Migration_Tool SHALL verify the gateway status is "RUNNING"
2. THE Migration_Tool SHALL output the new gateway IP and migration summary
3. WHEN platform is "ec2", THE Migration_Tool SHALL output the new instance ID
4. THE Migration_Tool SHALL provide clear next steps for DNS updates and old gateway cleanup

### Requirement 9: Rollback Support

**User Story:** As an infrastructure operator, I want clear rollback procedures, so that I can recover if the migration fails.

#### Acceptance Criteria

1. THE Migration_Tool SHALL document rollback steps in outputs when migration fails
2. WHEN platform is "ec2" and snapshots were created, THE Migration_Tool SHALL reference snapshot IDs in rollback instructions
3. WHEN platform is "vmware", THE Migration_Tool SHALL document VM snapshot restoration steps
4. THE Migration_Tool SHALL NOT automatically terminate/delete the old gateway

### Requirement 10: Ansible Prerequisites

**User Story:** As an infrastructure operator, I want clear prerequisites for Ansible execution, so that I can configure my environment correctly.

#### Acceptance Criteria

1. THE Migration_Tool SHALL document required Ansible version and dependencies
2. THE Migration_Tool SHALL provide inventory templates for both EC2 and VMware targets
3. THE Migration_Tool SHALL support SSH key-based authentication for VMware gateways
4. THE Migration_Tool SHALL support AWS SSM Session Manager plugin as Ansible connection for EC2
5. THE Migration_Tool SHALL include ansible.cfg with recommended settings

### Requirement 11: ec2-sgw Module Enhancements

**User Story:** As a module maintainer, I want the ec2-sgw module to support migration scenarios, so that migration examples can reuse existing module code.

#### Acceptance Criteria

1. THE ec2-sgw module SHALL add a `create_cache_volume` variable (default: true)
2. WHEN create_cache_volume is false, THE ec2-sgw module SHALL skip aws_ebs_volume and aws_volume_attachment resources
3. THE ec2-sgw module SHALL add a `create_eip` variable (default: true)
4. WHEN create_eip is false, THE ec2-sgw module SHALL skip aws_eip and aws_eip_association resources
5. THE ec2-sgw module SHALL add an `iam_instance_profile` variable to attach existing IAM profiles
6. THE ec2-sgw module SHALL output the instance_id for use by migration automation
