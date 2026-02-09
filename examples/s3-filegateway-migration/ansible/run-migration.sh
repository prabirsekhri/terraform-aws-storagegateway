#!/bin/bash
################################################################################
# Storage Gateway Migration Runner Script
# Extracts Terraform outputs and runs Ansible playbook
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Storage Gateway Migration Runner${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Activate virtual environment if it exists
VENV_DIR="$HOME/.ansible-venv"
if [ -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Activating Python virtual environment...${NC}"
    source "$VENV_DIR/bin/activate"
    echo -e "${GREEN}✓ Virtual environment activated${NC}"
    echo ""
else
    echo -e "${YELLOW}Note: Virtual environment not found at $VENV_DIR${NC}"
    echo "If you encounter issues, run: ./setup-ansible.sh"
    echo ""
fi

# Check if we're in the right directory
if [ ! -f "../main.tf" ]; then
    echo -e "${RED}Error: This script must be run from the ansible/ directory${NC}"
    echo "Current directory: $(pwd)"
    exit 1
fi

# Check if Terraform has been applied
if [ ! -f "../terraform.tfstate" ]; then
    echo -e "${RED}Error: Terraform state not found. Run 'terraform apply' first.${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Extracting Terraform outputs...${NC}"

# Extract values from Terraform outputs
cd ..
export OLD_INSTANCE_ID=$(terraform output -raw old_instance_id 2>/dev/null || echo "")
export NEW_INSTANCE_ID=$(terraform output -raw new_gateway_instance_id 2>/dev/null || echo "")
export GATEWAY_ID=$(terraform output -raw gateway_id 2>/dev/null || echo "")
export NEW_GATEWAY_PUBLIC_IP=$(terraform output -raw new_gateway_public_ip 2>/dev/null || echo "")
export NEW_GATEWAY_PRIVATE_IP=$(terraform output -raw new_gateway_private_ip 2>/dev/null || echo "")
export AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

# Use public IP if available, otherwise fall back to private IP
if [ -n "$NEW_GATEWAY_PUBLIC_IP" ] && [ "$NEW_GATEWAY_PUBLIC_IP" != "null" ]; then
    export NEW_GATEWAY_IP="$NEW_GATEWAY_PUBLIC_IP"
    echo -e "${GREEN}Using public IP for migration${NC}"
else
    export NEW_GATEWAY_IP="$NEW_GATEWAY_PRIVATE_IP"
    echo -e "${YELLOW}Using private IP for migration (ensure network connectivity)${NC}"
fi

cd ansible

# Validate required variables
if [ -z "$OLD_INSTANCE_ID" ] || [ -z "$NEW_INSTANCE_ID" ] || [ -z "$GATEWAY_ID" ] || [ -z "$NEW_GATEWAY_IP" ]; then
    echo -e "${RED}Error: Failed to extract required Terraform outputs${NC}"
    echo "OLD_INSTANCE_ID: $OLD_INSTANCE_ID"
    echo "NEW_INSTANCE_ID: $NEW_INSTANCE_ID"
    echo "GATEWAY_ID: $GATEWAY_ID"
    echo "NEW_GATEWAY_IP: $NEW_GATEWAY_IP"
    exit 1
fi

echo -e "${GREEN}✓ Terraform outputs extracted${NC}"
echo "  Old Instance: $OLD_INSTANCE_ID"
echo "  New Instance: $NEW_INSTANCE_ID"
echo "  Gateway ID: $GATEWAY_ID"
echo "  Gateway IP: $NEW_GATEWAY_IP"
echo "  Region: $AWS_REGION"
echo ""

# Check if Ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}Error: ansible-playbook not found. Please install Ansible.${NC}"
    echo "Install with: pip install ansible"
    exit 1
fi

echo -e "${YELLOW}Step 2: Checking Ansible collections...${NC}"

# Check if required collections are installed
if ! ansible-galaxy collection list | grep -q "amazon.aws"; then
    echo -e "${YELLOW}Installing required Ansible collections...${NC}"
    ansible-galaxy collection install -r requirements.yml
else
    echo -e "${GREEN}✓ Required collections already installed${NC}"
fi
echo ""

# Confirm before proceeding
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}WARNING: This will perform the following actions:${NC}"
echo -e "${YELLOW}========================================${NC}"
echo "1. Stop old gateway instance: $OLD_INSTANCE_ID"
echo "2. Detach all volumes from old instance"
echo "3. Attach cache volumes to new instance: $NEW_INSTANCE_ID"
echo "4. Attach old root volume temporarily"
echo "5. Start new instance and trigger migration"
echo "6. Stop new instance, detach old root volume"
echo "7. Start new instance (final)"
echo ""
echo -e "${YELLOW}This process will take approximately 15-20 minutes.${NC}"
echo -e "${YELLOW}The gateway will be offline during this time.${NC}"
echo ""

read -p "Do you want to proceed? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Migration cancelled.${NC}"
    exit 0
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Step 3: Running migration playbook...${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Run the Ansible playbook
ansible-playbook migrate.yml \
    -e "old_instance_id=$OLD_INSTANCE_ID" \
    -e "new_instance_id=$NEW_INSTANCE_ID" \
    -e "gateway_id=$GATEWAY_ID" \
    -e "new_gateway_ip=$NEW_GATEWAY_IP" \
    -e "aws_region=$AWS_REGION" \
    -v

PLAYBOOK_EXIT_CODE=$?

echo ""
if [ $PLAYBOOK_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Migration completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Verify gateway status in AWS Console"
    echo "2. Test file share access from clients"
    echo "3. If using Active Directory, re-join the domain"
    echo "4. Once verified, terminate old instance: $OLD_INSTANCE_ID"
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Migration failed with exit code: $PLAYBOOK_EXIT_CODE${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Check the output above for errors."
    echo "You may need to manually verify instance and volume states."
    exit $PLAYBOOK_EXIT_CODE
fi
