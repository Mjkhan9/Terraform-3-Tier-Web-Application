#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# TERRAFORM DRIFT DETECTION SCRIPT
# ═══════════════════════════════════════════════════════════════════════════════
# This script detects configuration drift between Terraform state and actual 
# AWS infrastructure. It should be run on a schedule (e.g., daily via cron or
# GitHub Actions) to catch manual changes that bypass IaC.
#
# Exit codes:
#   0 - No drift detected
#   1 - Drift detected
#   2 - Script error
#
# Usage:
#   ./scripts/drift-detection.sh
#   ./scripts/drift-detection.sh --json    # Output results as JSON
#   ./scripts/drift-detection.sh --slack   # Send alert to Slack
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Configuration
PROJECT_NAME="3-tier-web-app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DRIFT_LOG_DIR="${PROJECT_ROOT}/drift-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DRIFT_REPORT="${DRIFT_LOG_DIR}/drift-${TIMESTAMP}.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
OUTPUT_FORMAT="text"
SEND_SLACK="false"
for arg in "$@"; do
    case $arg in
        --json) OUTPUT_FORMAT="json" ;;
        --slack) SEND_SLACK="true" ;;
        --help) 
            echo "Usage: $0 [--json] [--slack]"
            exit 0
            ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[DRIFT]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        echo "Error: terraform is not installed"
        exit 2
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo "Error: aws-cli is not installed"
        exit 2
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "Error: AWS credentials not configured"
        exit 2
    fi
    
    log_success "Prerequisites check passed"
}

initialize_terraform() {
    log_info "Initializing Terraform..."
    cd "$PROJECT_ROOT"
    
    # Initialize without backend to avoid state locking issues
    terraform init -backend=false -input=false > /dev/null 2>&1 || {
        echo "Error: Terraform init failed"
        exit 2
    }
    
    log_success "Terraform initialized"
}

run_drift_detection() {
    log_info "Running drift detection..."
    
    mkdir -p "$DRIFT_LOG_DIR"
    
    # Run terraform plan and capture output
    # Using -detailed-exitcode: 0=no changes, 1=error, 2=changes detected
    set +e
    terraform plan \
        -detailed-exitcode \
        -input=false \
        -no-color \
        -var="db_password=placeholder" \
        > "$DRIFT_REPORT" 2>&1
    PLAN_EXIT_CODE=$?
    set -e
    
    return $PLAN_EXIT_CODE
}

analyze_drift() {
    local drift_file="$1"
    
    # Count different types of changes
    local resources_to_add=$(grep -c "will be created" "$drift_file" 2>/dev/null || echo "0")
    local resources_to_change=$(grep -c "will be updated" "$drift_file" 2>/dev/null || echo "0")
    local resources_to_destroy=$(grep -c "will be destroyed" "$drift_file" 2>/dev/null || echo "0")
    local resources_to_replace=$(grep -c "must be replaced" "$drift_file" 2>/dev/null || echo "0")
    
    echo "Resources to add:     $resources_to_add"
    echo "Resources to change:  $resources_to_change"
    echo "Resources to destroy: $resources_to_destroy"
    echo "Resources to replace: $resources_to_replace"
    
    # Extract specific resources with changes
    echo ""
    echo "Affected Resources:"
    grep -E "^  # |will be |must be " "$drift_file" 2>/dev/null | head -50 || true
}

check_security_group_drift() {
    log_info "Checking security group drift..."
    
    # Get security groups from Terraform state (if available)
    # Compare with actual AWS security groups
    local sg_changes=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --query 'SecurityGroups[*].[GroupId,GroupName]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$sg_changes" ]]; then
        log_info "Security Groups in AWS:"
        echo "$sg_changes"
    fi
}

check_instance_drift() {
    log_info "Checking EC2 instance drift..."
    
    # Get ASG instance details
    local asg_name="${PROJECT_NAME}-asg"
    
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --query 'AutoScalingGroups[0].{
            MinSize: MinSize,
            MaxSize: MaxSize,
            DesiredCapacity: DesiredCapacity,
            InstanceCount: length(Instances)
        }' \
        --output table 2>/dev/null || log_warning "ASG not found (may not be deployed)"
}

check_rds_drift() {
    log_info "Checking RDS drift..."
    
    local db_identifier="${PROJECT_NAME}-db"
    
    aws rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --query 'DBInstances[0].{
            Status: DBInstanceStatus,
            Class: DBInstanceClass,
            Engine: Engine,
            MultiAZ: MultiAZ,
            Encrypted: StorageEncrypted
        }' \
        --output table 2>/dev/null || log_warning "RDS instance not found (may not be deployed)"
}

generate_json_report() {
    local drift_detected="$1"
    local drift_file="$2"
    
    local resources_to_add=$(grep -c "will be created" "$drift_file" 2>/dev/null || echo "0")
    local resources_to_change=$(grep -c "will be updated" "$drift_file" 2>/dev/null || echo "0")
    local resources_to_destroy=$(grep -c "will be destroyed" "$drift_file" 2>/dev/null || echo "0")
    
    cat << EOF
{
  "timestamp": "$(date -Iseconds)",
  "project": "${PROJECT_NAME}",
  "drift_detected": ${drift_detected},
  "summary": {
    "resources_to_add": ${resources_to_add},
    "resources_to_change": ${resources_to_change},
    "resources_to_destroy": ${resources_to_destroy}
  },
  "report_file": "${drift_file}"
}
EOF
}

send_slack_notification() {
    local drift_detected="$1"
    local message="$2"
    
    if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
        log_warning "SLACK_WEBHOOK_URL not set, skipping Slack notification"
        return
    fi
    
    local color="good"
    local title="✅ No Infrastructure Drift Detected"
    
    if [[ "$drift_detected" == "true" ]]; then
        color="danger"
        title="🚨 Infrastructure Drift Detected"
    fi
    
    local payload=$(cat << EOF
{
  "attachments": [
    {
      "color": "${color}",
      "title": "${title}",
      "text": "${message}",
      "fields": [
        {
          "title": "Project",
          "value": "${PROJECT_NAME}",
          "short": true
        },
        {
          "title": "Timestamp",
          "value": "$(date)",
          "short": true
        }
      ],
      "footer": "Terraform Drift Detection"
    }
  ]
}
EOF
)

    curl -s -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK_URL" > /dev/null
        
    log_info "Slack notification sent"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  Terraform Drift Detection - ${PROJECT_NAME}"
    echo "  Timestamp: $(date)"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    
    check_prerequisites
    initialize_terraform
    
    # Run Terraform plan for drift detection
    run_drift_detection
    PLAN_EXIT_CODE=$?
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  DRIFT DETECTION RESULTS"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    
    case $PLAN_EXIT_CODE in
        0)
            log_success "No drift detected - Infrastructure matches Terraform configuration"
            
            if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                generate_json_report "false" "$DRIFT_REPORT"
            fi
            
            if [[ "$SEND_SLACK" == "true" ]]; then
                send_slack_notification "false" "All resources match Terraform configuration"
            fi
            
            exit 0
            ;;
        2)
            log_error "DRIFT DETECTED - Infrastructure has diverged from Terraform configuration"
            echo ""
            analyze_drift "$DRIFT_REPORT"
            
            if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                generate_json_report "true" "$DRIFT_REPORT"
            fi
            
            if [[ "$SEND_SLACK" == "true" ]]; then
                local drift_summary=$(grep -c "will be" "$DRIFT_REPORT" 2>/dev/null || echo "unknown")
                send_slack_notification "true" "Detected ${drift_summary} resource changes. See report: ${DRIFT_REPORT}"
            fi
            
            echo ""
            echo "Full report saved to: $DRIFT_REPORT"
            echo ""
            echo "To review changes:"
            echo "  cat $DRIFT_REPORT"
            echo ""
            echo "To remediate drift:"
            echo "  Option A: terraform apply      # Revert AWS to match Terraform"
            echo "  Option B: terraform import     # Update Terraform to match AWS"
            echo "  Option C: terraform refresh    # Update state only"
            
            exit 1
            ;;
        *)
            log_error "Terraform plan failed with error"
            cat "$DRIFT_REPORT"
            exit 2
            ;;
    esac
}

# Additional checks for specific resource types
run_additional_checks() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  ADDITIONAL INFRASTRUCTURE CHECKS"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    
    check_security_group_drift
    check_instance_drift
    check_rds_drift
}

# Execute main function
main

# Optionally run additional checks
if [[ "${RUN_ADDITIONAL_CHECKS:-false}" == "true" ]]; then
    run_additional_checks
fi

