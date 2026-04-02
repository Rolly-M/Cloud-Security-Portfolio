#!/bin/bash

###############################################################################
# GuardDuty Lab - Quick Cleanup Script
# For lab/test environments only - deletes everything without archiving
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       GuardDuty Lab - Quick Cleanup (No Data Retention)        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Type 'destroy' to confirm: " confirm
if [ "$confirm" != "destroy" ]; then
    echo "Cancelled."
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

echo -e "\n${YELLOW}[1/4] Getting S3 bucket name...${NC}"
cd "$TERRAFORM_DIR"
BUCKET_NAME=$(terraform output -raw findings_bucket_name 2>/dev/null || echo "")

echo -e "${YELLOW}[2/4] Emptying S3 bucket...${NC}"
if [ -n "$BUCKET_NAME" ]; then
    aws s3 rb "s3://$BUCKET_NAME" --force 2>/dev/null || true
    echo -e "${GREEN}Bucket deleted${NC}"
else
    echo "No bucket found"
fi

echo -e "${YELLOW}[3/4] Destroying Terraform resources...${NC}"
cd "$TERRAFORM_DIR"
terraform destroy -auto-approve

echo -e "${YELLOW}[4/4] Cleaning local files...${NC}"
rm -rf .terraform .terraform.lock.hcl terraform.tfstate* *.tfplan 2>/dev/null || true
rm -f "$SCRIPT_DIR/lambda/remediation_handler.zip" 2>/dev/null || true

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Lab Cleanup Complete!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"