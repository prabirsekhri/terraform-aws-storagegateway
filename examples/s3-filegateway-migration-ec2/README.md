<!-- BEGIN_TF_DOCS -->
# EC2 File Gateway Migration

Example demonstrates how to migrate an existing EC2-based S3 File Gateway to a new instance — whether your data and performance needs grow, you upgrade to a newer host platform (e.g., AL2 to AL2023), or refresh underlying hardware. The migration procedure preserves your cache disks and Gateway ID by following [Method 1](https://docs.aws.amazon.com/filegateway/latest/files3/migrate-data.html) from the File Gateway documentation.

## Overview

This migration method:

- Preserves cache disk data (useful for large caches or read-intensive applications)
- Maintains the same Gateway configuration (preserving the Gateway and File share IDs)
- Allows specifying instance type for the new gateway
- Requires 1-2 hours of downtime

The migration is split into two phases:

### Phase 1: Infrastructure Provisioning (Terraform)

Terraform deploys the latest version of the gateway EC2 instance alongside the existing gateway. The only required input is `gateway_id` (e.g., `sgw-12A3456B`). A helper script (`get-gateway-instance.sh`) uses the Gateway ID to look up the underlying EC2 instance via the Storage Gateway API, and Terraform then pulls all the networking and configuration details — VPC, subnet, AZ, security group, SSH key, and root disk settings — directly from that instance. Terraform does not touch the old instance or its volumes — it only creates the new instance and outputs the information needed for Phase 2.

**Phase 1 outputs (Terraform):**

| Output | Description |
|--------|-------------|
| `migration_summary` | Combined summary: gateway ID, old/new instance IDs, instance types, root disk sizes, VPC/subnet/AZ, and cache volume IDs |
| `new_gateway_instance_id` | EC2 instance ID of the new AL2023 gateway |
| `new_gateway_private_ip` | Private IP of the new gateway (used by the Ansible playbook to trigger migration) |
| `new_gateway_public_ip` | Public IP of the new gateway (sensitive; only present if an EIP is attached) |
| `old_instance_id` | EC2 instance ID of the old gateway (discovered from `gateway_id`) |
| `gateway_id` | The Storage Gateway ID being migrated |
| `aws_region` | AWS region where the migration is taking place |
| `migration_url` | Pre-built HTTP URL to trigger the migration API (`http://<private_ip>/migrate?gatewayId=<id>`) |
| `next_steps` | Instructions for running the Ansible playbook |

### Phase 2: Migration Execution (Ansible)

The Ansible playbook handles the actual migration process: stopping the old instance, detaching and reattaching EBS volumes (cache disks + old root) to the new instance, triggering the migration API, cleaning up the old root volume, and optionally rejoining the Gateway to Active Directory (Steps 3 - 15 from the [Method #1](https://docs.aws.amazon.com/filegateway/latest/files3/migrate-data.html) migration approach). This separation keeps the destructive/stateful operations out of Terraform and in an idempotent playbook that can be re-run if something fails mid-way.

> **Important:** The playbook detaches but does not delete the old root volume after migration. Once you have confirmed the migration is successful (see Post-Migration Validation below), you should manually delete the old root volume (shown in Terraform output via `migration_summary`) to avoid unnecessary storage costs.

**Phase 2 outputs (Ansible):**

| Output | Description |
|--------|-------------|
| Migration information | Old/new instance IDs, gateway ID, gateway IP, and region |
| Cache dirty check | Current `CachePercentDirty` metric from CloudWatch with risk assessment |
| Port 80 connectivity | Reachability status of the new gateway's migration API endpoint |
| Volume classification | Breakdown of root disk vs cache disks with volume IDs, sizes, and device mappings |
| Volume configuration file | Timestamped `migration-volumes-<epoch>.txt` file saved to the `ansible/` directory |
| Attachment results | Per-volume success/failure status for root and cache disk attachments |
| Migration API response | Success or failure of the `http://<ip>/migrate?gatewayId=<id>` call |
| Final instance state | New instance volume layout after old root detach and restart |
| SMB/AD status | Active Directory domain join status and SMB settings (if applicable) |
| Migration log | Full playbook output saved to `ansible/logs/migration-<gateway_id>-<timestamp>.log` |

## Prerequisites

Before running this example, ensure:

1. **Stop all applications writing to the gateway**
   - Ensure no active write operations

2. **Gateway is updated to the latest version**
   - Check in AWS Console: Storage Gateway > Gateways > Select gateway > Update Now

3. **CachePercentDirty metric is 0**
   - Check in AWS Console: Storage Gateway > Gateways > Select gateway > Monitoring tab
   - Wait for all cached data to be uploaded to S3
   - The Ansible playbook also checks this metric and warns you before proceeding

4. **AWS CLI and `jq` installed**
   - The `get-gateway-instance.sh` helper script uses both to discover the EC2 instance from the gateway ID

5. **Port 80 connectivity to the gateway instance**
   - The Ansible playbook triggers migration via an HTTP call to the gateway on port 80
   - Ensure the security group and network ACLs allow inbound port 80 from wherever the playbook runs
   - The Ansible playbook also checks the port 80 connectivity to the gateway instance and warns you before proceeding

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
# gateway_type  = "FILE_S3"      # FILE_S3 (default: FILE_S3)
# instance_type = "m7i.xlarge"   # New instance type (default: same as old gateway)

# Optional: Configure DNS on the new gateway at launch via admincli. For AD-authenticated/SMB gateways, this user-data script helps configure the AD DNS server for the domain join to succeed in the migration process.
# Sample user-data script to configure DNS server
# user_data = <<-EOF
#   #!/bin/bash
#   sudo /usr/bin/admincli dns static --primary-dns 10.0.0.2 ens5
# EOF
```

#### Step 1a: User Data for Network Configuration

The optional `user_data` variable allows you to run a script at instance launch via cloud-init to configure network settings using the gateway's built-in `admincli` tool. This is particularly useful for AD-authenticated/SMB gateways where the AD DNS server must be configured for the domain join to succeed during migration.

The network interface name depends on the instance platform: Nitro-based instances use `ens5`, Xen-based instances use `eth0`. The user-data is automatically base64-encoded by the module.

All other configuration (VPC, subnet, AZ, security group, SSH key, root disk) is automatically discovered from the existing gateway instance.

#### Step 2: Initialize and Plan

```bash
terraform init
terraform plan
```

Review the plan to ensure:

- New gateway instance will be created in the same subnet/AZ as the old gateway
- The existing security group from the old instance will be reused
- No new cache volume or EIP will be created (volumes are migrated from the old instance)

#### Step 3: Apply Infrastructure

```bash
terraform apply
```

This provisions:

- New Storage Gateway EC2 instance (using the latest AMI from SSM parameter)
- Root disk matching the old gateway's configuration
- Reuses the old instance's security group

```hcl
 # Migration-specific settings - don't create new cache volume or EIP
  create_cache_volume = false
  create_eip          = false

  # Use existing security group from old instance
  create_security_group = false
  security_group_id     = tolist(data.aws_instance.old_sgw.vpc_security_group_ids)[0]
```

### Phase 2: Migration Execution

After Terraform completes, the new Gateway instance is running but the migration hasn't happened yet. Phase 2 moves the volumes and triggers the actual migration.

Use the provided Ansible playbook to automate the migration:

```bash
cd ansible/
chmod +x run-migration.sh
./run-migration.sh
```

The `run-migration.sh` script extracts Terraform outputs, validates prerequisites, and runs the Ansible playbook. The playbook will:

1. Discover the old instance ID from the gateway ID (if not provided via env var)
2. Check CachePercentDirty metric and warn if data hasn't been fully flushed
3. Verify port 80 connectivity to the new Gateway instance
4. Discover and classify volumes (root vs cache) attached to the old instance
5. Stop the old gateway instance
6. Detach all volumes from the old instance
7. Attach cache volumes and old root volume to the new (running) instance
8. Trigger migration via the gateway HTTP API
9. On success: stop the new instance, detach the old root volume, restart
10. Check SMB settings and Active Directory domain join status
11. If the gateway was previously joined to AD, prompt for credentials and rejoin

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

> **Note:** Detailed migration logs are stored in `ansible/logs/` with timestamped filenames (e.g., `migration-sgw-12A3456B-20260320_194500.log`). Review these logs for troubleshooting if the migration encounters any issues.

## Architecture

```text
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

## Terraform Outputs

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

## Post-Migration Validation

After the migration completes, verify everything is working correctly:

1. Check gateway status in the AWS Console — navigate to Storage Gateway > Gateways and confirm the gateway shows "Running"
2. Verify file shares are accessible from clients by mounting and listing files
3. Confirm cache disks are recognized — check CloudWatch `CacheUsed` and `CacheHitPercent` metrics
4. Test read/write operations on file shares to ensure data integrity
5. Monitor `CachePercentDirty` to confirm new writes are being uploaded to S3

## Old Root Volume Cleanup

The Ansible playbook automatically detaches the old root volume (`/dev/sdf`) from the new instance after a successful migration, but it does not delete it. This is intentional — the volume serves as a safety net in case you need to investigate issues.

Once you have completed the post-migration validation steps above and are confident the migration succeeded:

```bash
# Find the old root volume ID from Terraform output
terraform output migration_summary

# Delete the old root volume (replace with your volume ID)
aws ec2 delete-volume --volume-id vol-0123456789abcdef0
```

You should also consider terminating the old gateway EC2 instance once you are satisfied with the migration.

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

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |
| <a name="provider_external"></a> [external](#provider\_external) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_new_sgw"></a> [new\_sgw](#module\_new\_sgw) | ../../modules/ec2-sgw | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_ebs_volumes.cache_volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ebs_volumes) | data source |
| [aws_instance.old_sgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/instance) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.old_sgw_subnet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [external_external.gateway_instance](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_gateway_id"></a> [gateway\_id](#input\_gateway\_id) | The Storage Gateway ID (e.g., sgw-12A3456B) of the gateway to migrate. The EC2 instance ID will be automatically discovered. | `string` | n/a | yes |
| <a name="input_gateway_type"></a> [gateway\_type](#input\_gateway\_type) | Type of the gateway. Valid options are FILE\_S3 | `string` | `"FILE_S3"` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Instance type for the new AL2023 gateway. If not specified, uses the same type as the old gateway. Recommended: m7i.xlarge, m7i.2xlarge, r7i.xlarge, etc. | `string` | `null` | no |
| <a name="input_root_block_device"></a> [root\_block\_device](#input\_root\_block\_device) | Root block device configuration of the new instance will match the old gateway's root disk configuration. | `map(any)` | `{}` | no |
| <a name="input_user_data"></a> [user\_data](#input\_user\_data) | User data script for gateway network configuration via admincli (e.g., DNS) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_region"></a> [aws\_region](#output\_aws\_region) | The AWS region where the migration is taking place |
| <a name="output_gateway_id"></a> [gateway\_id](#output\_gateway\_id) | The Storage Gateway ID being migrated |
| <a name="output_migration_summary"></a> [migration\_summary](#output\_migration\_summary) | Summary of the migration process |
| <a name="output_migration_url"></a> [migration\_url](#output\_migration\_url) | URL to initiate the gateway migration process |
| <a name="output_new_gateway_instance_id"></a> [new\_gateway\_instance\_id](#output\_new\_gateway\_instance\_id) | The EC2 instance ID of the new Storage Gateway |
| <a name="output_new_gateway_private_ip"></a> [new\_gateway\_private\_ip](#output\_new\_gateway\_private\_ip) | The private IP address of the new Storage Gateway |
| <a name="output_new_gateway_public_ip"></a> [new\_gateway\_public\_ip](#output\_new\_gateway\_public\_ip) | The public IP address of the new Storage Gateway |
| <a name="output_next_steps"></a> [next\_steps](#output\_next\_steps) | Next steps to complete the migration |
| <a name="output_old_instance_id"></a> [old\_instance\_id](#output\_old\_instance\_id) | The EC2 instance ID of the old Storage Gateway |
<!-- END_TF_DOCS -->