#!/bin/bash

###############################################################################
# GuardDuty Project - Complete Environment Cleanup Script
#
# This script safely destroys all resources created by the GuardDuty
# auto-remediation project and cleans up any artifacts.
#
# Usage: ./cleanup.sh [--force]
#   --force: Skip confirmation prompt
#
# WARNING: This action cannot be undone!
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
SIMULATION_DIR="$SCRIPT_DIR/threat-simulation"
LAMBDA_DIR="$SCRIPT_DIR/lambda"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} \$1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} \$1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} \$1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} \$1"
}

# Header
print_header() {
    echo -e "${RED}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║       GuardDuty Project - Environment Cleanup                  ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    echo "║  This script will:                                             ║"
    echo "║  • Archive all GuardDuty findings                              ║"
    echo "║  • Delete forensic snapshots                                   ║"
    echo "║  • Empty and delete S3 buckets                                 ║"
    echo "║  • Destroy all Terraform resources                             ║"
    echo "║  • Clean up CloudWatch log groups                              ║"
    echo "║  • Remove local Terraform state files                          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Confirmation prompt
confirm_cleanup() {
    if [ "\$1" == "--force" ]; then
        return 0
    fi

    echo -e "${YELLOW}This action will permanently destroy all resources.${NC}"
    echo ""
    read -p "Type 'destroy' to confirm: " confirm

    if [ "$confirm" != "destroy" ]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi

    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Please install it first."
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_warning "jq not found. Some cleanup steps may be limited."
    fi

    log_success "Prerequisites check passed"
}

# Archive GuardDuty findings
archive_findings() {
    log_info "Archiving GuardDuty findings..."

    DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null)

    if [ -z "$DETECTOR_ID" ] || [ "$DETECTOR_ID" == "None" ]; then
        log_warning "No GuardDuty detector found"
        return 0
    fi

    FINDING_IDS=$(aws guardduty list-findings \
        --detector-id "$DETECTOR_ID" \
        --finding-criteria '{"Criterion":{"service.archived":{"Eq":["false"]}}}' \
        --query 'FindingIds' \
        --output text 2>/dev/null)

    if [ -n "$FINDING_IDS" ] && [ "$FINDING_IDS" != "None" ]; then
        IFS=' ' read -ra IDS <<< "$FINDING_IDS"

        for ((i=0; i<${#IDS[@]}; i+=50)); do
            BATCH="${IDS[@]:i:50}"
            aws guardduty archive-findings \
                --detector-id "$DETECTOR_ID" \
                --finding-ids $BATCH 2>/dev/null || true
        done

        log_success "Archived ${#IDS[@]} findings"
    else
        log_info "No active findings to archive"
    fi
}

# Delete forensic snapshots
delete_forensic_snapshots() {
    log_info "Deleting forensic snapshots..."

    SNAPSHOTS=$(aws ec2 describe-snapshots \
        --filters "Name=tag:CreatedBy,Values=GuardDuty-Auto-Remediation" \
        --query 'Snapshots[*].SnapshotId' \
        --output text 2>/dev/null)

    if [ -n "$SNAPSHOTS" ] && [ "$SNAPSHOTS" != "None" ]; then
        for SNAP_ID in $SNAPSHOTS; do
            log_info "  Deleting snapshot: $SNAP_ID"
            aws ec2 delete-snapshot --snapshot-id "$SNAP_ID" 2>/dev/null || true
        done
        log_success "Deleted forensic snapshots"
    else
        log_info "No forensic snapshots found"
    fi
}

# Check for quarantined instances
check_quarantined_instances() {
    log_info "Checking for quarantined instances..."

    QUARANTINED=$(aws ec2 describe-instances \
        --filters "Name=tag:SecurityStatus,Values=QUARANTINED" \
        --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`OriginalSecurityGroups`].Value|[0]]' \
        --output text 2>/dev/null)

    if [ -n "$QUARANTINED" ] && [ "$QUARANTINED" != "None" ]; then
        log_warning "Found quarantined instances:"
        echo "$QUARANTINED" | while read -r line; do
            echo "    $line"
        done
        echo ""
        log_warning "Please manually review and restore/terminate these instances"
        read -p "Press Enter to continue..."
    else
        log_info "No quarantined instances found"
    fi
}

# Get Terraform outputs before destroy
get_terraform_outputs() {
    log_info "Getting Terraform outputs..."

    cd "$TERRAFORM_DIR"

    if [ ! -f "terraform.tfstate" ] && [ ! -d ".terraform" ]; then
        log_warning "No Terraform state found"
        return 1
    fi

    terraform init -input=false &>/dev/null || true

    BUCKET_NAME=$(terraform output -raw findings_bucket_name 2>/dev/null || echo "")
    LAMBDA_NAME=$(terraform output -raw lambda_function_name 2>/dev/null || echo "")

    export BUCKET_NAME
    export LAMBDA_NAME

    log_success "Retrieved Terraform outputs"
}

# Empty S3 bucket
empty_s3_bucket() {
    if [ -z "$BUCKET_NAME" ]; then
        log_warning "No S3 bucket to empty"
        return 0
    fi

    log_info "Emptying S3 bucket: $BUCKET_NAME"

    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        log_warning "Bucket $BUCKET_NAME does not exist"
        return 0
    fi

    aws s3 rm "s3://$BUCKET_NAME" --recursive 2>/dev/null || true

    if command -v jq &> /dev/null; then
        aws s3api list-object-versions --bucket "$BUCKET_NAME" --output json 2>/dev/null | \
        jq -r '.Versions[]? | "\(.Key)\t\(.VersionId)"' | \
        while IFS=$'\t' read -r key version; do
            aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version" 2>/dev/null || true
        done

        aws s3api list-object-versions --bucket "$BUCKET_NAME" --output json 2>/dev/null | \
        jq -r '.DeleteMarkers[]? | "\(.Key)\t\(.VersionId)"' | \
        while IFS=$'\t' read -r key version; do
            aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version" 2>/dev/null || true
        done
    fi

    log_success "S3 bucket emptied"
}

# Destroy Terraform infrastructure
destroy_terraform() {
    log_info "Destroying Terraform infrastructure..."

    cd "$TERRAFORM_DIR"

    if [ ! -f "terraform.tfstate" ] && [ ! -d ".terraform" ]; then
        log_warning "No Terraform state found, skipping destroy"
        return 0
    fi

    terraform init -input=false &>/dev/null || true

    terraform destroy -auto-approve

    log_success "Terraform infrastructure destroyed"
}

# Delete CloudWatch log groups
delete_log_groups() {
    log_info "Deleting CloudWatch log groups..."

    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/guardduty-security" \
        --query 'logGroups[*].logGroupName' \
        --output text 2>/dev/null)

    if [ -n "$LOG_GROUPS" ] && [ "$LOG_GROUPS" != "None" ]; then
        for LG in $LOG_GROUPS; do
            log_info "  Deleting log group: $LG"
            aws logs delete-log-group --log-group-name "$LG" 2>/dev/null || true
        done
        log_success "CloudWatch log groups deleted"
    else
        log_info "No matching log groups found"
    fi
}

# Clean up IAM quarantine policies
cleanup_iam_policies() {
    log_info "Checking for IAM quarantine policies..."

    USERS=$(aws iam list-users --query 'Users[*].UserName' --output text 2>/dev/null)

    FOUND_POLICIES=false
    for USER in $USERS; do
        if aws iam get-user-policy --user-name "$USER" --policy-name "GuardDuty-Quarantine-DenyAll" &>/dev/null; then
            log_info "  Removing quarantine policy from user: $USER"
            aws iam delete-user-policy --user-name "$USER" --policy-name "GuardDuty-Quarantine-DenyAll" 2>/dev/null || true
            FOUND_POLICIES=true
        fi
    done

    if [ "$FOUND_POLICIES" = true ]; then
        log_success "IAM quarantine policies removed"
    else
        log_info "No IAM quarantine policies found"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."

    cd "$TERRAFORM_DIR"

    rm -rf .terraform 2>/dev/null || true
    rm -f .terraform.lock.hcl 2>/dev/null || true
    rm -f terraform.tfstate 2>/dev/null || true
    rm -f terraform.tfstate.backup 2>/dev/null || true
    rm -f *.tfplan 2>/dev/null || true
    rm -f crash.log 2>/dev/null || true

    rm -f "$LAMBDA_DIR/remediation_handler.zip" 2>/dev/null || true

    log_success "Local files cleaned up"
}

# Verification
verify_cleanup() {
    log_info "Verifying cleanup..."

    echo ""
    echo "Verification Results:"
    echo "────────────────────────────────────────────────"

    DETECTORS=$(aws guardduty list-detectors --query 'DetectorIds' --output text 2>/dev/null || echo "Error")
    echo "  GuardDuty Detectors: ${DETECTORS:-None}"

    S3_COUNT=$(aws s3 ls 2>/dev/null | grep -c "guardduty-security" || echo "0")
    echo "  GuardDuty S3 Buckets: $S3_COUNT"

    LAMBDAS=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `guardduty-security`)].FunctionName' \
        --output text 2>/dev/null || echo "None")
    echo "  GuardDuty Lambda Functions: ${LAMBDAS:-None}"

    SNS_COUNT=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `guardduty`)].TopicArn' --output text 2>/dev/null | wc -w || echo "0")
    echo "  GuardDuty SNS Topics: $SNS_COUNT"

    RULES=$(aws events list-rules \
        --query 'Rules[?contains(Name, `guardduty-security`)].Name' \
        --output text 2>/dev/null || echo "None")
    echo "  GuardDuty EventBridge Rules: ${RULES:-None}"

    echo "────────────────────────────────────────────────"
}

# Print completion message
print_completion() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Environment Cleanup Completed Successfully!           ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Note: KMS keys are scheduled for deletion (7-30 days)"
    log_info "Check your AWS console to verify all resources are removed"
}

# Main execution
main() {
    print_header
    confirm_cleanup "\$1"

    echo ""
    log_info "Starting cleanup process..."
    echo ""

    check_prerequisites

    echo ""
    echo "────────────────────────────────────────────────"
    echo "Step 1/9: Archive GuardDuty Findings"
    echo "────────────────────────────────────────────────"
    archive_findings

    echo ""
    echo "────────────────────────────────────────────────"
    echo "Step 2/9: Delete Forensic Snapshots"
    echo "────────────────────────────────────────────────"
    delete_forensic_snapshots

    echo ""
    echo "────────────────────────────────────────────────"
    echo "Step 3/9: Check Quarantined Instances"
    echo "────────────────────────────────────────────────"
    check_quarantined_instances

    echo ""
    echo "────────────────────────────────────────────────"
    echo "Step 4/9: Get Terraform Outputs"
    echo "────────────────────────────────────────────────"
    get_terraform_outputs || true

    echo ""
    echo "────────────────────────────────────────────────"
    echo "Step 5/9: Empty S3 Bucket"
    echo "────────────────────────────────────────────────"
    empty_s3_bucket

    echo ""
    echo "────────────────────────────────────────────────"
    echo "Step 6/9: Destroy Terraform Infrastructure"
    echo "────────────────────────────────────────────────"
    destroy_terraform

    echo ""
    echo "────────────────────────────────────────────────"
    echo "Step 7/9: Delete CloudWatch Log Groups"
    echo "────────────────────────────────────────────────"
    delete_log_groups

    echo ""
    echo "────────────────────────────────────────────────"
    echo "Step 8/9: Cleanup IAM Policies"
    echo "────────────────────────────────────────────────"
    cleanup_iam_policies

    echo ""
    echo "────────────────────────────────────────────────"
    echo "Step 9/9: Cleanup Local Files"
    echo "────────────────────────────────────────────────"
    cleanup_local_files

    echo ""
    verify_cleanup
    print_completion
}

# Run main function
main "$@"