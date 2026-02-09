# S3 File Gateway Migration Example - Method 1

This example demonstrates how to migrate an existing Amazon Linux 2 (AL2) Storage Gateway to Amazon Linux 2023 (AL2023) while preserving cache disks and the Gateway ID, following AWS's [Method 1 migration approach](https://docs.aws.amazon.com/filegateway/latest/files3/migrate-data.html).

## Overview

This migration method:
- ✅ Preserves cache disk data (useful for large caches or latency-sensitive applications)
- ✅ Maintains the same Gateway ID
- ✅ Allows specifying instance type for the new gateway
- ✅ Reuses existing Elastic IP
- ⏱️ Requires 1-2 hours of downtime

## Prerequisites

Before running this example, ensure:

1. **Gateway is updated to the latest version**
   - Check in AWS Console: Storage Gateway → Gateways → Select gateway → Update Now

2. **CachePercentDirty metric is 0**
   - Check in AWS Console: Storage Gateway → Gateways → Select gateway → Monitoring tab
   - Wait for all cached data to be uploaded to S3

3. **Stop all applications writing to the gateway**
   - Ensure no active write operations

4. **Old gateway instance is STOPPED**
   ```bash
   aws ec2 stop-instances --instance-ids i-0123456789abcdef0
   ```

5. **Gather required information**
   - Gateway ID (e.g., `sgw-12A3456B`)
   - Old instance ID (e.g., `i-0123456789abcdef0`)
   - VPC ID (e.g., `vpc-0123456789abcdef0`)

## Usage

### Step 1: Configure Variables

Copy the example tfvars file and update with your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
gateway_id      = "sgw-12A3456B"
old_instance_id = "i-0123456789abcdef0"
vpc_id          = "vpc-0123456789abcdef0"
gateway_type    = "FILE_S3"

# Optional settings
instance_type = "m7i.xlarge"  # Specify new instance type (or omit to keep same)
reuse_eip     = true          # Reattach existing Elastic IP
```

### Step 2: Initialize and Plan

```bash
terraform init
terraform plan
```

Review the plan to ensure:
- New AL2023 instance will be created
- Cache volumes will be attached
- Snapshots will be created (if enabled)
- EIP will be reattached (if enabled)

### Step 3: Apply Infrastructure

```bash
terraform apply
```

This provisions:
- New AL2023 Storage Gateway EC2 instance
- Volume attachments for cache disks
- EIP association (optional)

### Step 4: Complete Migration

After Terraform completes, you have two options:

#### **Option A: Automated Migration with Ansible (Recommended)**

Use the provided Ansible playbook to automate all manual steps:

```bash
cd ansible/
chmod +x run-migration.sh
./run-migration.sh
```

The Ansible playbook will automatically:
1. ✅ Stop old gateway instance
2. ✅ Detach cache and root volumes from old instance
3. ✅ Attach cache volumes to new instance
4. ✅ Attach old root volume temporarily
5. ✅ Start new instance
6. ✅ Wait for gateway API to be ready
7. ✅ Trigger migration via HTTP API
8. ✅ Stop new instance and detach old root volume
9. ✅ Start new instance (final)

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

#### **Option B: Manual Migration**

If you prefer manual control, follow these steps:

1. **Initiate migration** using one of these methods:

   **Option A: Local Console**
   - Access the new gateway's local console
   - Select "Migrate Gateway"
   - Enter your gateway ID when prompted

   **Option B: Web Request**
   ```bash
   # Get the migration URL from Terraform output
   terraform output migration_url
   
   # Use curl to initiate migration
   curl "http://<new-gateway-ip>/migrate?gatewayId=sgw-12A3456B"
   ```

2. **Wait for gateway status** to show "Running" in AWS Console (up to 10 minutes)

3. **Stop the new gateway instance**
   ```bash
   NEW_INSTANCE_ID=$(terraform output -raw new_gateway_instance_id)
   aws ec2 stop-instances --instance-ids $NEW_INSTANCE_ID
   ```

4. **Detach old gateway's root disk**
   ```bash
   # Find the old root disk attached to new instance
   aws ec2 describe-volumes \
     --filters "Name=attachment.instance-id,Values=$NEW_INSTANCE_ID" \
     --query "Volumes[?Attachments[0].Device=='/dev/sda1'].VolumeId" \
     --output text
   
   # Detach it (use the volume ID from above)
   aws ec2 detach-volume --volume-id vol-xxxxxxxxx
   ```

5. **Start the new gateway instance**
   ```bash
   aws ec2 start-instances --instance-ids $NEW_INSTANCE_ID
   ```

6. **Re-join Active Directory** (if applicable)
   - Follow instructions in [AWS Documentation](https://docs.aws.amazon.com/filegateway/latest/files3/managing-gateway-file.html#join-domain)

7. **Re-enter SMB Guest Access password** (if applicable)

8. **Verify shares are accessible**
   ```bash
   # Test NFS mount
   showmount -e <new-gateway-ip>
   
   # Test SMB share
   smbclient -L <new-gateway-ip> -U <username>
   ```

9. **Delete old gateway VM**
   ```bash
   # Terminate old instance
   aws ec2 terminate-instances --instance-ids i-0123456789abcdef0
   ```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Migration Process                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Old AL2 Gateway (STOPPED)                                  │
│  ┌──────────────────────────────────────┐                   │
│  │  Instance: i-old                     │                   │
│  │  Type: m5.xlarge                     │                   │
│  │  ├─ Root Disk (80GB)                 │                   │
│  │  ├─ Cache Disk 1 (150GB) ───────┐    │                   │
│  │  └─ Cache Disk 2 (150GB) ───┐   │    │                   │
│  └──────────────────────────────│───│────┘                   │
│                                 │   │                        │
│                    Detach & Reattach                         │
│                                 │   │                        │
│  New AL2023 Gateway             │   │                        │
│  ┌──────────────────────────────│───│────┐                   │
│  │  Instance: i-new             ▼   ▼    │                   │
│  │  Type: m7i.xlarge            │   │    │                   │
│  │  ├─ Root Disk (80GB)         │   │    │                   │
│  │  ├─ Cache Disk 1 (150GB) ◄───┘   │    │                   │
│  │  └─ Cache Disk 2 (150GB) ◄───────┘    │                   │
│  └──────────────────────────────────────┘                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Recommended Instance Types

For AL2023 Storage Gateways, AWS recommends using the latest generation instance types:

### General Purpose (M7i family)
- `m7i.xlarge` - 4 vCPUs, 16 GB RAM
- `m7i.2xlarge` - 8 vCPUs, 32 GB RAM
- `m7i.4xlarge` - 16 vCPUs, 64 GB RAM
- `m7i.8xlarge` - 32 vCPUs, 128 GB RAM

### Memory Optimized (R7i family)
- `r7i.xlarge` - 4 vCPUs, 32 GB RAM
- `r7i.2xlarge` - 8 vCPUs, 64 GB RAM
- `r7i.4xlarge` - 16 vCPUs, 128 GB RAM
- `r7i.8xlarge` - 32 vCPUs, 256 GB RAM

**Migration Recommendations:**
- M5 instances → M7i equivalent (e.g., m5.xlarge → m7i.xlarge)
- R5 instances → R7i equivalent (e.g., r5.2xlarge → r7i.2xlarge)
- If `instance_type` is not specified, the new gateway will use the same type as the old gateway

## Outputs

After applying, Terraform provides:

```bash
# View migration summary
terraform output migration_summary

# Get new instance ID
terraform output new_gateway_instance_id

# Get migration URL
terraform output migration_url

# View next steps
terraform output next_steps
```

## Troubleshooting

### Issue: "Instance must be stopped"
**Solution:** Ensure the old gateway instance is fully stopped before running `terraform apply`

### Issue: "CachePercentDirty is not 0"
**Solution:** Wait for all cached data to upload to S3. Monitor the metric in AWS Console.

### Issue: "Volume attachment failed"
**Solution:** Ensure volumes are detached from the old instance. Check volume state with:
```bash
aws ec2 describe-volumes --volume-ids vol-xxxxxxxxx
```

### Issue: "Migration URL not responding"
**Solution:** 
- Verify the new instance is running
- Check security group allows access on port 80
- Ensure you're accessing from an allowed CIDR block

## Cleanup

To remove the migration infrastructure (after successful migration):

```bash
# This will destroy the new gateway - only do this if migration failed
terraform destroy
```

**Note:** Do not run `terraform destroy` after a successful migration, as it will terminate your new gateway!

## References

- [AWS Storage Gateway Migration Documentation](https://docs.aws.amazon.com/filegateway/latest/files3/migrate-data.html)
- [Storage Gateway Requirements](https://docs.aws.amazon.com/filegateway/latest/files3/Requirements.html)
- [EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| new_sgw | ../../modules/ec2-sgw | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| gateway_id | The Storage Gateway ID of the gateway to migrate | `string` | n/a | yes |
| old_instance_id | The EC2 instance ID of the existing AL2 Storage Gateway | `string` | n/a | yes |
| vpc_id | The VPC ID where the gateway is deployed | `string` | n/a | yes |
| gateway_type | Type of the gateway (FILE_S3, VTL, CACHED, STORED) | `string` | `"FILE_S3"` | no |
| instance_type | Instance type for the new AL2023 gateway (if not specified, uses same as old) | `string` | `null` | no |
| reuse_eip | Reattach the existing Elastic IP from the old gateway | `bool` | `true` | no |
| root_block_device | Root block device configuration | `map(any)` | See variables.tf | no |

## Outputs

| Name | Description |
|------|-------------|
| migration_summary | Summary of the migration process |
| new_gateway_instance_id | The EC2 instance ID of the new AL2023 Storage Gateway |
| new_gateway_private_ip | The private IP address of the new Storage Gateway |
| new_gateway_public_ip | The public IP address of the new Storage Gateway |
| migration_url | URL to initiate the gateway migration process |
| next_steps | Detailed next steps to complete the migration |
