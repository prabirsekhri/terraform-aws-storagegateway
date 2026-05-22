#!/bin/bash
################################################################################
# Script to get EC2 instance ID from Storage Gateway ID
# Uses AWS CLI to call DescribeGatewayInformation API
################################################################################

set -e

# Read input from Terraform
eval "$(jq -r '@sh "GATEWAY_ID=\(.gateway_id) AWS_REGION=\(.aws_region)"')"

# Construct gateway ARN
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
GATEWAY_ARN="arn:aws:storagegateway:${AWS_REGION}:${ACCOUNT_ID}:gateway/${GATEWAY_ID}"

# Call DescribeGatewayInformation API
GATEWAY_INFO=$(aws storagegateway describe-gateway-information \
  --gateway-arn "$GATEWAY_ARN" \
  --region "$AWS_REGION" \
  --output json 2>/dev/null || echo "{}")

# Extract EC2 instance ID
INSTANCE_ID=$(echo "$GATEWAY_INFO" | jq -r '.Ec2InstanceId // empty')

# If instance ID not found, return error
if [ -z "$INSTANCE_ID" ]; then
  echo "{\"error\": \"Could not find EC2 instance ID for gateway ${GATEWAY_ID}\"}" >&2
  exit 1
fi

# Return JSON output for Terraform
jq -n --arg instance_id "$INSTANCE_ID" '{"instance_id":$instance_id}'
