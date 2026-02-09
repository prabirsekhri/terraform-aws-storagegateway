# Ansible Automation for Storage Gateway Migration

This directory contains Ansible playbooks to automate the manual steps of the Storage Gateway AL2023 migration process.

## What It Does

The Ansible playbook automates the following steps after Terraform provisioning:

1. ✅ **Stop old gateway instance**
2. ✅ **Detach cache and root volumes** from old instance
3. ✅ **Attach cache volumes** to new instance
4. ✅ **Attach old root volume** temporarily to new instance
5. ✅ **Start new instance**
6. ✅ **Wait for gateway API** to be ready
7. ✅ **Trigger migration** via HTTP API call
8. ✅ **Stop new instance** after migration
9. ✅ **Detach old root volume** from new instance
10. ✅ **Start new instance** (final)

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

#### Phase 1: Stop Old Instance
- Checks current state
- Stops instance if running
- Waits for stopped state

#### Phase 2: Detach Volumes
- Discovers all attached volumes
- Identifies root volume (/dev/sda1)
- Identifies cache volumes (/dev/sdb, /dev/sdc, etc.)
- Detaches all volumes
- Waits for volumes to be available

#### Phase 3: Attach Cache Volumes
- Attaches each cache volume to new instance
- Preserves original device names
- Waits for attachment completion

#### Phase 4: Attach Root Volume (Temporary)
- Attaches old root volume to new instance at /dev/sdf
- This is required for the migration process
- Will be detached later

#### Phase 5: Start New Instance
- Starts new gateway instance
- Waits for running state
- Waits for instance checks to pass

#### Phase 6: Wait for Gateway API
- Polls gateway HTTP endpoint
- Retries up to 60 times (10 minutes)
- Confirms gateway is ready

#### Phase 7: Trigger Migration
- Calls migration URL: `http://<ip>/migrate?gatewayId=<id>`
- Waits for response (up to 10 minutes)
- Pauses 5 minutes for migration to complete

#### Phase 8: Stop Instance
- Stops new instance to detach old root volume

#### Phase 9: Detach Old Root Volume
- Detaches old root volume from new instance
- Waits for volume to be available

#### Phase 10: Final Start
- Starts new instance with only its own root volume
- Migration is complete!

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

Most tasks are idempotent and safe to re-run:
- ✅ Stopping already-stopped instances (skipped)
- ✅ Detaching already-detached volumes (skipped)
- ✅ Attaching already-attached volumes (skipped)
- ⚠️ Migration API call (may fail if already migrated)

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
        "ec2:DetachVolume"
      ],
      "Resource": "*"
    }
  ]
}
```

## Files

```
ansible/
├── migrate.yml              # Main migration playbook
├── ansible.cfg              # Ansible configuration
├── requirements.yml         # Required Ansible collections
├── run-migration.sh         # Convenience runner script
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
   ```bash
   # NFS
   showmount -e $NEW_GATEWAY_IP
   
   # SMB
   smbclient -L $NEW_GATEWAY_IP -U username
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
