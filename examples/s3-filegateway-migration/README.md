# EC2 File Gateway Migration 

This example demonstrates how to migrate an existing Amazon Linux 2 (AL2) Storage Gateway to Amazon Linux 2023 (AL2023) while preserving cache disks and the Gateway ID, following AWS's [Method 1 migration approach](https://docs.aws.amazon.com/filegateway/latest/files3/migrate-data.html).

## Overview

This migration method:
- Preserves cache disk data (useful for large caches or read intensive applications)
- Maintains the same Gateway ID
- Allows specifying instance type for the new gateway
- Requires 1-2 hours of downtime

The migration is split into two phases:

### Phase 1: Infrastructure Provisioning (Terraform)

Terraform deploys the new AL2023 gateway EC2 instance alongside the existing AL2 gateway. The only required input is `gateway_id` (e.g., `sgw-12A3456B`). Everything else — the old EC2 instance ID, VPC, subnet, AZ, security group, SSH key, and root disk settings — is automatically discovered from the gateway. Terraform does not touch the old instance or its volumes — it only creates the new instance and outputs the information needed for Phase 2.

### Phase 2: Migration Execution (Ansible)

The Ansible playbook handles the actual migration process: stopping the old instance, detaching and reattaching EBS volumes (cache disks + old root) to the new instance, triggering the migration API, cleaning up the old root volume, and optionally rejoining the Gateway to Active Directory. This separation keeps the destructive/stateful operations out of Terraform and in an idempotent playbook that can be re-run if something fails mid-way.

## Prerequisites

Before running this example, ensure:

1. **Gateway is updated to the latest version**
   - Check in AWS Console: Storage Gateway > Gateways > Select gateway > Update Now

2. **CachePercentDirty metric is 0**
   - Check in AWS Console: Storage Gateway > Gateways > Select gateway > Monitoring tab
   - Wait for all cached data to be uploaded to S3
   - The Ansible playbook also checks this metric and warns you before proceeding

3. **Stop all applications writing to the gateway**
   - Ensure no active write operations

4. **AWS CLI and `jq` installed**
   - The `get-gateway-instance.sh` helper script uses both to discover the EC2 instance from the gateway ID

5. **Port 80 connectivity to the gateway instance**
   - The Ansible playbook triggers migration via an HTTP call to the gateway on port 80
   - Ensure the security group and network ACLs allow inbound port 80 from wherever the playbook runs

6. **Gather required information**
   - Gateway ID (e.g., `sgw-12A3456B`)

## Usage

### Phase 1: Infrastructure Provisioning (Terraform)

#### Step 1: Configure Variables

At minimum, you only need to provide the `gateway_id`. Copy the example tfvars file and update:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# Only required variable — everything else is auto-discovered from the gateway
gateway_id = "sgw-12A3456B"

# Optional settings
# gateway_type  = "FILE_S3"      # FILE_S3 or CACHED (default: FILE_S3)
# instance_type = "m7i.xlarge"   # New instance type (default: same as old gateway)
# reuse_eip     = false          # Reattach existing Elastic IP (default: false)
```

All other configuration (VPC, subnet, AZ, security group, SSH key, root disk) is automatically discovered from the existing gateway instance.

#### Step 2: Initialize and Plan

```bash
terraform init
terraform plan
```

Review the plan to ensure:
- New AL2023 instance will be created in the same subnet/AZ as the old gateway
- The existing security group from the old instance will be reused
- No new cache volume or EIP will be created (volumes are migrated from the old instance)

#### Step 3: Apply Infrastructure

```bash
terraform apply
```

This provisions:
- New AL2023 Storage Gateway EC2 instance (using the latest AMI from SSM parameter)
- Root disk matching the old gateway's configuration
- Reuses the old instance's security group

### Phase 2: Migration Execution

After Terraform completes, the new AL2023 instance is running but the migration hasn't happened yet. Phase 2 moves the volumes and triggers the actual migration.

Use the provided Ansible playbook to automate the migration:

```bash
cd ansible/
chmod +x run-migration.sh
./run-migration.sh
```

The `run-migration.sh` script extracts Terraform outputs, validates prerequisites, and runs the Ansible playbook. The playbook will:

1. Discover the old instance ID from the gateway ID (if not provided via env var)
2. Check CachePercentDirty metric and warn if data hasn't been fully flushed
3. Discover and classify volumes (root vs cache) attached to the old instance
4. Stop the old gateway instance
5. Detach all volumes from the old instance
6. Attach cache volumes and old root volume to the new (running) instance
7. Trigger migration via the gateway HTTP API
8. On success: stop the new instance, detach the old root volume, restart
9. Check SMB settings and Active Directory domain join status
10. If the gateway was previously joined to AD, prompt for credentials and rejoin

**Prerequisites for Ansible:**
```bash
# Install Ansible
pip install ansible

# Install required collections
cd ansible/
ansible-galaxy collection install -r requirements.yml

# Ensure AWS credentials are configured
aws configure
```

See [ansible/README.md](ansible/README.md) for detailed documentation.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Migration Process                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Old AL2 Gateway (STOPPED)                                  │
│  ┌──────────────────────────────────────┐                   │
│  │  Instance: i-old                     │                   │
│  │  ├─ Root Disk (/dev/sda1)            │                   │
│  │  ├─ Cache Disk 1 (/dev/sdb) ────┐    │                   │
│  │  └─ Cache Disk 2 (/dev/sdc) ─┐  │    │                   │
│  └───────────────────────────────│──│────┘                   │
│                                  │  │                        │
│                   Detach & Reattach                          │
│                                  │  │                        │
│  New AL2023 Gateway              │  │                        │
│  ┌───────────────────────────────│──│────┐                   │
│  │  Instance: i-new              ▼  ▼    │                   │
│  │  ├─ AL2023 Root (/dev/xvda)           │                   │
│  │  ├─ Old Root (/dev/sdf) *temporary*   │                   │
│  │  ├─ Cache Disk 1 (/dev/sdg) ◄────────│                   │
│  │  └─ Cache Disk 2 (/dev/sdh) ◄────────│                   │
│  └───────────────────────────────────────┘                   │
│                                                              │
│  * Old root is detached after migration completes            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Recommended Instance Types

For AL2023 Storage Gateways, AWS recommends using the latest generation instance types:

| Old Type | Recommended Replacement | vCPUs | RAM |
|----------|------------------------|-------|-----|
| m5.xlarge | m7i.xlarge | 4 | 16 GB |
| m5.2xlarge | m7i.2xlarge | 8 | 32 GB |
| m5.4xlarge | m7i.4xlarge | 16 | 64 GB |
| r5.xlarge | r7i.xlarge | 4 | 32 GB |
| r5.2xlarge | r7i.2xlarge | 8 | 64 GB |
| r5.4xlarge | r7i.4xlarge | 16 | 128 GB |

If `instance_type` is not specified, the new gateway will use the same type as the old gateway.

## Outputs

After applying, Terraform provides:

```bash
# View migration summary (gateway ID, instance IDs, types, volumes, etc.)
terraform output migration_summary

# Get new instance ID
terraform output new_gateway_instance_id

# Get old instance ID (auto-discovered)
terraform output old_instance_id

# Get migration URL
terraform output migration_url

# View next steps
terraform output next_steps
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Could not find EC2 instance ID for gateway" | Verify the gateway ID is correct and AWS credentials have `storagegateway:DescribeGatewayInformation` permission. Ensure `jq` is installed. |
| "CachePercentDirty is not 0" | Wait for all cached data to upload to S3. Monitor the metric in CloudWatch. |
| "Volume attachment failed" | Ensure volumes are detached from the old instance and in the same AZ. Check with `aws ec2 describe-volumes`. |
| "Migration URL not responding" | Verify the new instance is running, security group allows port 80, and you can reach the instance IP. |
| "Cache disk count mismatch" | The migration API expects all original cache volumes attached. Verify all cache disks are attached to the new instance at `/dev/sdg+`. |

## Cleanup

To remove the migration infrastructure (after successful migration):

```bash
# Only do this if migration FAILED and you need to start over
terraform destroy
```

Do not run `terraform destroy` after a successful migration, as it will terminate your new gateway.

## References

- [AWS Storage Gateway Migration Documentation](https://docs.aws.amazon.com/filegateway/latest/files3/migrate-data.html)
- [Storage Gateway Requirements](https://docs.aws.amazon.com/filegateway/latest/files3/Requirements.html)
- [EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |
| external | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| new\_sgw | ../../modules/ec2-sgw | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| gateway\_id | The Storage Gateway ID (e.g., sgw-12A3456B) of the gateway to migrate. The EC2 instance ID will be automatically discovered. | `string` | n/a | yes |
| gateway\_type | Type of the gateway. Valid options are FILE\_S3, CACHED | `string` | `"FILE_S3"` | no |
| instance\_type | Instance type for the new AL2023 gateway. If not specified, uses the same type as the old gateway. Recommended: m7i.xlarge, m7i.2xlarge, r7i.xlarge, etc. | `string` | `null` | no |
| reuse\_eip | Reattach the existing Elastic IP from the old gateway to the new gateway | `bool` | `false` | no |
| root\_block\_device | Root block device configuration of the new instance will match the old gateway's root disk configuration. | `map(any)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| migration\_summary | Summary of the migration process |
| new\_gateway\_instance\_id | The EC2 instance ID of the new Storage Gateway |
| new\_gateway\_private\_ip | The private IP address of the new Storage Gateway |
| new\_gateway\_public\_ip | The public IP address of the new Storage Gateway |
| old\_instance\_id | The EC2 instance ID of the old Storage Gateway (auto-discovered) |
| gateway\_id | The Storage Gateway ID being migrated |
| aws\_region | The AWS region where the migration is taking place |
| migration\_url | URL to initiate the gateway migration process |
| next\_steps | Next steps to complete the migration |

<!-- END_TF_DOCS -->
