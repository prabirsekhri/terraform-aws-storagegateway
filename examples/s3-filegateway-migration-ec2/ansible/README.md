# Ansible Automation for Storage Gateway Migration

This directory contains Ansible playbooks to automate the manual steps of the Storage Gateway AL2023 migration process.

## What It Does

The Ansible playbook automates the following steps after Terraform provisioning:

1. ✅ **Discover old instance ID** from Gateway ID (if not provided)
2. ✅ **Check CachePercentDirty** metric and warn if data hasn't been fully flushed
3. ✅ **Verify port 80 connectivity** to the new gateway instance
4. ✅ **Discover and classify volumes** (root vs cache) attached to the old instance
5. ✅ **Stop old gateway instance**
6. ✅ **Detach all volumes** from old instance
7. ✅ **Verify new instance is running**
8. ✅ **Attach cache volumes and old root volume** to the new instance
9. ✅ **Update gateway IP** (refresh after any IP changes)
10. ✅ **Trigger migration** via the gateway HTTP API
11. ✅ **Confirm migration** complete
12. ✅ **Detach old root volume**, stop/start new instance
13. ✅ **Check SMB settings** and Active Directory domain join status
14. ✅ **Rejoin Active Directory** domain (if previously joined)

## Prerequisites

### 1. Install Ansible

```bash
# Using pip
pip install ansible

# Using homebrew (macOS)
brew install ansible

# Verify installation
ansible --version
```

### 2. Install Required Collections

```bash
cd ansible/
ansible-galaxy collection install -r requirements.yml
```

This installs:
- `amazon.aws` - AWS modules for Ansible
- `community.aws` - Additional AWS community modules

### 3. Configure AWS Credentials

Ensure your AWS credentials are configured:

```bash
# Option 1: AWS CLI configuration
aws configure

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_SESSION_TOKEN="your-session-token"  # If using temporary credentials

# Option 3: AWS credentials file
# ~/.aws/credentials
[default]
aws_access_key_id = your-access-key
aws_secret_access_key = your-secret-key
```

### 4. Run Terraform First

The Ansible playbook requires Terraform outputs:

```bash
cd ..  # Go to migration example root
terraform init
terraform apply
```

## Usage

### Option 1: Using the Runner Script (Recommended)

The easiest way to run the migration:

```bash
cd ansible/
chmod +x run-migration.sh
./run-migration.sh
```

The script will:
- Extract Terraform outputs automatically
- Validate prerequisites
- Show a summary of actions
- Ask for confirmation
- Run the Ansible playbook
- Display results

### Option 2: Manual Execution

If you prefer to run Ansible directly:

```bash
cd ansible/

# Set environment variables from Terraform outputs
export OLD_INSTANCE_ID=$(cd .. && terraform output -raw old_instance_id)
export NEW_INSTANCE_ID=$(cd .. && terraform output -raw new_gateway_instance_id)
export GATEWAY_ID=$(cd .. && terraform output -raw gateway_id)
export NEW_GATEWAY_IP=$(cd .. && terraform output -raw new_gateway_private_ip)
export AWS_REGION=$(cd .. && terraform output -raw aws_region)

# Run the playbook
ansible-playbook migrate.yml
```

### Option 3: With Custom Variables

Override variables at runtime:

```bash
ansible-playbook migrate.yml \
  -e "old_instance_id=i-0123456789abcdef0" \
  -e "new_instance_id=i-fedcba9876543210" \
  -e "gateway_id=sgw-12A3456B" \
  -e "new_gateway_ip=10.0.1.50" \
  -e "aws_region=us-east-1" \
  -v
```

## Playbook Details

### Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `old_instance_id` | EC2 instance ID of old AL2 gateway | Terraform output |
| `new_instance_id` | EC2 instance ID of new AL2023 gateway | Terraform output |
| `gateway_id` | Storage Gateway ID (e.g., sgw-12A3456B) | Terraform output |
| `new_gateway_ip` | Private IP of new gateway | Terraform output |
| `aws_region` | AWS region | Terraform output or env var |
| `migration_timeout` | Timeout for migration API call (seconds) | Default: 600 |

### Tasks Breakdown

#### Step 1: Discover Old Instance ID
- Looks up the EC2 instance ID from the Gateway ID via the Storage Gateway API
- Skipped if `old_instance_id` is provided via environment variable

#### Step 2: Check Cache Dirty Percentage
- Queries CloudWatch for the `CachePercentDirty` metric
- Warns if data hasn't been fully flushed to S3
- Prompts for confirmation if cache dirty is above 0%

#### Step 3: Verify Port 80 Connectivity
- Tests TCP connectivity to the new gateway instance on port 80
- Fails early with troubleshooting steps if unreachable
- Prevents wasted effort if the migration API won't be accessible

#### Step 4: Discover Volumes
- Discovers all EBS volumes attached to the old instance
- Classifies them as root (has AMI snapshot) or cache (no snapshot)
- Saves volume configuration to a timestamped file

#### Step 5: Stop Old Gateway Instance
- Checks current state and stops the old instance
- Waits for stopped state confirmation

#### Step 6: Detach All Volumes
- Detaches all volumes (root + cache) from the old instance
- Waits for each volume to reach 'available' state

#### Step 7: Verify New Instance is Running
- Confirms the new AL2023 instance is in 'running' state
- Fails if the instance is not running

#### Step 8: Attach All Volumes
- Attaches old root volume to `/dev/sdf`
- Attaches cache volumes to `/dev/sdg`, `/dev/sdh`, etc.
- Validates all cache disks are attached with correct count

#### Step 9: Update Gateway IP
- Refreshes the gateway IP address (may change after restarts)

#### Step 10: Trigger Migration
- Calls `http://<ip>/migrate?gatewayId=<id>`
- Validates the response for success or failure
- Reports cache disk mismatch errors if detected

#### Step 11: Confirm Migration Complete
- Displays migration summary with volume configuration

#### Step 12: Detach Old Root Volume
- Stops the new instance
- Detaches the old root volume (`/dev/sdf`)
- Restarts the new instance
- Displays final volume configuration

#### Step 13: Check SMB / Active Directory Status
- Retrieves SMB settings from the gateway
- Reports AD domain join status

#### Step 14: Rejoin Active Directory
- If the gateway was previously joined to AD, prompts for credentials
- Rejoins the gateway to the AD domain
- Skipped if the gateway was not AD-joined

## Execution Time

Expected duration: **15-20 minutes**

Breakdown:
- Stop old instance: 1-2 minutes
- Detach volumes: 1-2 minutes
- Attach volumes: 2-3 minutes
- Start instance: 1-2 minutes
- Wait for API: 2-5 minutes
- Migration process: 5-10 minutes
- Final restart: 1-2 minutes

## Output Example

```
TASK [Display migration information] *******************************************
ok: [localhost] => {
    "msg": [
        "Starting Storage Gateway Migration",
        "Old Instance: i-0123456789abcdef0",
        "New Instance: i-fedcba9876543210",
        "Gateway ID: sgw-12A3456B",
        "New Gateway IP: 10.0.1.50",
        "Region: us-east-1"
    ]
}

TASK [Stop old gateway instance] ***********************************************
changed: [localhost]

TASK [Detach root volume from old instance] ************************************
changed: [localhost]

...

TASK [Confirm migration complete] **********************************************
ok: [localhost] => {
    "msg": [
        "==========================================",
        "Migration Complete!",
        "==========================================",
        "New Instance: i-fedcba9876543210",
        "Gateway ID: sgw-12A3456B",
        "Gateway IP: 10.0.1.50"
    ]
}
```

## Troubleshooting

### Issue: "Required environment variables are missing"
**Solution:** Ensure Terraform has been applied and outputs are available:
```bash
cd .. && terraform output
```

### Issue: "Failed to connect to gateway API"
**Solution:** 
- Check security group allows access from your IP
- Verify new instance is running
- Check VPC routing and network ACLs

### Issue: "Migration API call timed out"
**Solution:**
- Increase `migration_timeout` variable
- Check gateway logs in AWS Console
- Verify CachePercentDirty was 0 before starting

### Issue: "Volume attachment failed"
**Solution:**
- Ensure volumes are in 'available' state
- Check volume is in same AZ as instance
- Verify IAM permissions for EC2 volume operations

### Issue: "Playbook fails mid-execution"
**Solution:**
- Check AWS Console for resource states
- Re-run playbook (it's idempotent for most tasks)
- Manually verify and fix any stuck resources

## Idempotency

The playbook includes a built-in recovery mode: if no volumes are found on the old instance but volumes are already attached to the new instance, it skips the stop/detach/attach steps and jumps straight to the migration trigger. This handles the most common mid-run failure scenario.

**Fully idempotent (safe to re-run):**
- Step 1 — Gateway discovery: read-only API call, no side effects
- Step 2 — Cache dirty check: read-only CloudWatch query, no side effects
- Step 3 — Port 80 connectivity: TCP probe only, includes private IP fallback
- Step 4 — Volume discovery and classification: read-only, writes a new timestamped config file each run
- Step 5 — Stop old instance: skipped if already stopped (`when: state != 'stopped'`)
- Step 6 — Detach volumes: skipped in recovery mode; `ec2_vol` with `instance: ""` is a no-op on already-detached volumes
- Step 7 — Verify new instance running: read-only assert
- Step 8 — Attach volumes: skipped in recovery mode; `ec2_vol` attach is a no-op if volume is already attached to the same instance at the same device
- Step 9 — Update gateway IP: read-only instance info refresh


## Required IAM Permissions

The AWS credentials used must have these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeVolumes",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "storagegateway:DescribeGatewayInformation",
        "storagegateway:DescribeSMBSettings",
        "storagegateway:ListGateways",
        "storagegateway:JoinDomain",
        "cloudwatch:GetMetricStatistics",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## Files

```
ansible/
├── migrate.yml              # Main migration playbook (14 steps)
├── ansible.cfg              # Ansible configuration
├── requirements.yml         # Required Ansible collections
├── run-migration.sh         # Convenience runner script
├── logs/                    # Timestamped migration logs
├── inventory/
│   └── localhost.yml        # Localhost inventory
└── README.md               # This file
```

## Next Steps After Migration

1. **Verify Gateway Status**
   ```bash
   aws storagegateway describe-gateway-information \
     --gateway-arn "arn:aws:storagegateway:region:account:gateway/$GATEWAY_ID"
   ```

2. **Test File Shares**

   First, get the file share details from the gateway:
   ```bash
   # List all file shares on the gateway
   aws storagegateway list-file-shares \
     --gateway-arn "arn:aws:storagegateway:$AWS_REGION:$ACCOUNT_ID:gateway/$GATEWAY_ID"
   ```

   **NFS shares:**
   ```bash
   # Verify NFS exports are available
   showmount -e $NEW_GATEWAY_IP

   # Mount and test (Linux/macOS)
   sudo mkdir -p /mnt/sgw-nfs
   sudo mount -t nfs -o nolock,hard $NEW_GATEWAY_IP:/<s3-bucket-name> /mnt/sgw-nfs
   ls /mnt/sgw-nfs
   ```

   **SMB shares:**
   ```bash
   # List available SMB shares
   smbclient -L $NEW_GATEWAY_IP -U username

   # Mount on Linux
   sudo mkdir -p /mnt/sgw-smb
   sudo mount -t cifs //$NEW_GATEWAY_IP/<share-name> /mnt/sgw-smb \
     -o username=<domain-user>,password=<password>,domain=<domain-name>
   ls /mnt/sgw-smb
   ```

   **SMB on Windows (map network drive):**
   ```powershell
   # Map as a network drive
   net use Z: \\<NEW_GATEWAY_IP>\<share-name> /user:<domain-name>\<username> <password>

   # Or use File Explorer:
   # 1. Open File Explorer → right-click "This PC" → "Map network drive"
   # 2. Drive: Z: (or any available letter)
   # 3. Folder: \\<NEW_GATEWAY_IP>\<share-name>
   # 4. Check "Connect using different credentials"
   # 5. Enter domain\username and password
   ```

   **SMB on macOS (Finder):**
   ```
   # From Finder: Go → Connect to Server (⌘K)
   # Enter: smb://<NEW_GATEWAY_IP>/<share-name>
   # Authenticate with domain credentials

   # Or from terminal:
   open smb://<domain-user>@<NEW_GATEWAY_IP>/<share-name>
   ```

3. **Re-join Active Directory** (if applicable)
   - Use AWS Console or CLI to re-join domain

4. **Re-enter SMB Guest Password** (if applicable)
   - Use AWS Console to update guest password

5. **Delete Old Instance** (after verification)
   ```bash
   aws ec2 terminate-instances --instance-ids $OLD_INSTANCE_ID
   ```

## Support

For issues or questions:
- Check AWS Storage Gateway documentation
- Review Ansible playbook output for specific errors
- Verify AWS resource states in Console
- Check CloudWatch logs for gateway errors
