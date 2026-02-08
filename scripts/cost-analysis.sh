#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# AWS COST ANALYSIS SCRIPT
# ═══════════════════════════════════════════════════════════════════════════════
# Analyzes current and projected AWS costs for the 3-tier web application.
# Uses Cost Explorer API and local Terraform configuration to provide
# accurate cost estimates and optimization recommendations.
#
# Prerequisites:
#   - AWS CLI v2 with Cost Explorer access
#   - ce:GetCostAndUsage permission
#   - Terraform (for resource counting)
#
# Usage:
#   ./scripts/cost-analysis.sh
#   ./scripts/cost-analysis.sh --detailed
#   ./scripts/cost-analysis.sh --forecast
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Configuration
PROJECT_NAME="3-tier-web-app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
DETAILED="false"
FORECAST="false"
for arg in "$@"; do
    case $arg in
        --detailed) DETAILED="true" ;;
        --forecast) FORECAST="true" ;;
        --help)
            echo "Usage: $0 [--detailed] [--forecast]"
            echo "  --detailed  Show per-service cost breakdown"
            echo "  --forecast  Show 30-day cost forecast"
            exit 0
            ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════
# COST CONSTANTS (AWS Published Pricing - us-east-1)
# ═══════════════════════════════════════════════════════════════════════════════

# EC2 Pricing (On-Demand, us-east-1)
declare -A EC2_HOURLY_COST=(
    ["t3.micro"]="0.0104"
    ["t3.small"]="0.0208"
    ["t3.medium"]="0.0416"
    ["t2.micro"]="0.0116"
    ["m5.large"]="0.096"
)

# RDS Pricing (On-Demand, us-east-1)
declare -A RDS_HOURLY_COST=(
    ["db.t3.micro"]="0.017"
    ["db.t3.small"]="0.034"
    ["db.t3.medium"]="0.068"
    ["db.m5.large"]="0.171"
)

# Other service costs (monthly)
NAT_GATEWAY_MONTHLY="32.40"        # $0.045/hour
NAT_GATEWAY_DATA_GB="0.045"        # Per GB processed
ALB_MONTHLY="16.20"                # $0.0225/hour
ALB_LCU_HOURLY="0.008"             # Per LCU-hour
S3_STORAGE_GB="0.023"              # Per GB/month
CLOUDWATCH_LOGS_GB="0.50"          # Per GB ingested
VPC_ENDPOINT_MONTHLY="7.20"        # Interface endpoint

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────${NC}"
}

format_currency() {
    printf "$%.2f" "$1"
}

calculate_monthly_cost() {
    local hourly_cost="$1"
    echo "scale=2; $hourly_cost * 730" | bc  # 730 hours/month average
}

# ═══════════════════════════════════════════════════════════════════════════════
# RESOURCE DISCOVERY
# ═══════════════════════════════════════════════════════════════════════════════

get_ec2_costs() {
    print_section "EC2 Instances"
    
    # Get instances from ASG
    local asg_info
    asg_info=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "${PROJECT_NAME}-asg" \
        --query 'AutoScalingGroups[0].{
            DesiredCapacity: DesiredCapacity,
            MinSize: MinSize,
            MaxSize: MaxSize
        }' \
        --output json 2>/dev/null || echo '{"DesiredCapacity": 2, "MinSize": 2, "MaxSize": 4}')
    
    local desired_capacity=$(echo "$asg_info" | jq -r '.DesiredCapacity // 2')
    local instance_type="t3.micro"  # Default from variables.tf
    
    # Get instance type from launch template if available
    local lt_instance_type
    lt_instance_type=$(aws ec2 describe-launch-template-versions \
        --launch-template-name "${PROJECT_NAME}-" \
        --versions '$Latest' \
        --query 'LaunchTemplateVersions[0].LaunchTemplateData.InstanceType' \
        --output text 2>/dev/null || echo "t3.micro")
    
    if [[ "$lt_instance_type" != "None" && -n "$lt_instance_type" ]]; then
        instance_type="$lt_instance_type"
    fi
    
    local hourly_cost="${EC2_HOURLY_COST[$instance_type]:-0.0104}"
    local monthly_per_instance=$(calculate_monthly_cost "$hourly_cost")
    local total_ec2_monthly=$(echo "scale=2; $monthly_per_instance * $desired_capacity" | bc)
    
    echo "  Instance Type:     $instance_type"
    echo "  Running Instances: $desired_capacity"
    echo "  Hourly Cost/each:  \$${hourly_cost}"
    echo "  Monthly/each:      \$${monthly_per_instance}"
    echo -e "  ${GREEN}Total EC2 Monthly:  \$${total_ec2_monthly}${NC}"
    
    EC2_TOTAL="$total_ec2_monthly"
}

get_rds_costs() {
    print_section "RDS Database"
    
    local db_instance_class="db.t3.micro"  # Default from variables.tf
    local storage_gb="20"
    local multi_az="false"
    
    # Try to get actual RDS info
    local rds_info
    rds_info=$(aws rds describe-db-instances \
        --db-instance-identifier "${PROJECT_NAME}-db" \
        --query 'DBInstances[0].{
            Class: DBInstanceClass,
            Storage: AllocatedStorage,
            MultiAZ: MultiAZ
        }' \
        --output json 2>/dev/null || echo '{}')
    
    if [[ "$rds_info" != "{}" ]]; then
        db_instance_class=$(echo "$rds_info" | jq -r '.Class // "db.t3.micro"')
        storage_gb=$(echo "$rds_info" | jq -r '.Storage // 20')
        multi_az=$(echo "$rds_info" | jq -r '.MultiAZ // false')
    fi
    
    local hourly_cost="${RDS_HOURLY_COST[$db_instance_class]:-0.017}"
    local monthly_compute=$(calculate_monthly_cost "$hourly_cost")
    
    # Multi-AZ doubles the cost
    if [[ "$multi_az" == "true" ]]; then
        monthly_compute=$(echo "scale=2; $monthly_compute * 2" | bc)
    fi
    
    # Storage cost: $0.115/GB/month for gp2
    local monthly_storage=$(echo "scale=2; $storage_gb * 0.115" | bc)
    local total_rds=$(echo "scale=2; $monthly_compute + $monthly_storage" | bc)
    
    echo "  Instance Class:    $db_instance_class"
    echo "  Storage:           ${storage_gb} GB"
    echo "  Multi-AZ:          $multi_az"
    echo "  Compute Cost:      \$${monthly_compute}/month"
    echo "  Storage Cost:      \$${monthly_storage}/month"
    echo -e "  ${GREEN}Total RDS Monthly:  \$${total_rds}${NC}"
    
    RDS_TOTAL="$total_rds"
}

get_nat_gateway_costs() {
    print_section "NAT Gateways"
    
    # Count NAT gateways
    local nat_count
    nat_count=$(aws ec2 describe-nat-gateways \
        --filter "Name=tag:Name,Values=*${PROJECT_NAME}*" "Name=state,Values=available" \
        --query 'length(NatGateways)' \
        --output text 2>/dev/null || echo "2")
    
    if [[ "$nat_count" == "None" || -z "$nat_count" ]]; then
        nat_count="2"  # Default from Terraform config
    fi
    
    local monthly_base=$(echo "scale=2; $NAT_GATEWAY_MONTHLY * $nat_count" | bc)
    # Estimate data processing (10GB/day * 30 days)
    local estimated_data_gb="300"
    local data_cost=$(echo "scale=2; $estimated_data_gb * $NAT_GATEWAY_DATA_GB" | bc)
    local total_nat=$(echo "scale=2; $monthly_base + $data_cost" | bc)
    
    echo "  NAT Gateways:      $nat_count"
    echo "  Base Cost/each:    \$${NAT_GATEWAY_MONTHLY}/month"
    echo "  Est. Data (GB):    $estimated_data_gb"
    echo "  Data Cost:         \$${data_cost}"
    echo -e "  ${GREEN}Total NAT Monthly:  \$${total_nat}${NC}"
    echo ""
    echo -e "  ${YELLOW}💡 TIP: Set enable_nat_gateway=false to save \$${total_nat}/month${NC}"
    echo -e "  ${YELLOW}   (Use VPC Endpoints for AWS service access instead)${NC}"
    
    NAT_TOTAL="$total_nat"
}

get_alb_costs() {
    print_section "Application Load Balancer"
    
    local alb_monthly="$ALB_MONTHLY"
    # Estimate LCU usage (1-2 LCU for typical small app)
    local estimated_lcu="1.5"
    local lcu_monthly=$(echo "scale=2; $estimated_lcu * $ALB_LCU_HOURLY * 730" | bc)
    local total_alb=$(echo "scale=2; $alb_monthly + $lcu_monthly" | bc)
    
    echo "  Base Cost:         \$${alb_monthly}/month"
    echo "  Est. LCU Usage:    $estimated_lcu LCU"
    echo "  LCU Cost:          \$${lcu_monthly}"
    echo -e "  ${GREEN}Total ALB Monthly:  \$${total_alb}${NC}"
    
    ALB_TOTAL="$total_alb"
}

get_vpc_endpoint_costs() {
    print_section "VPC Endpoints"
    
    # Count interface endpoints
    local endpoint_count
    endpoint_count=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=tag:Name,Values=*${PROJECT_NAME}*" "Name=vpc-endpoint-type,Values=Interface" \
        --query 'length(VpcEndpoints)' \
        --output text 2>/dev/null || echo "3")
    
    if [[ "$endpoint_count" == "None" || -z "$endpoint_count" ]]; then
        endpoint_count="3"  # SSM, CloudWatch, Secrets Manager
    fi
    
    # Gateway endpoints (S3) are free
    local total_endpoints=$(echo "scale=2; $VPC_ENDPOINT_MONTHLY * $endpoint_count" | bc)
    
    echo "  Interface Endpoints: $endpoint_count"
    echo "  Cost/endpoint:       \$${VPC_ENDPOINT_MONTHLY}/month"
    echo "  Gateway Endpoints:   FREE (S3)"
    echo -e "  ${GREEN}Total VPC Endpoints: \$${total_endpoints}${NC}"
    
    VPC_ENDPOINT_TOTAL="$total_endpoints"
}

get_other_costs() {
    print_section "Other Services"
    
    # S3 (estimate 1GB storage)
    local s3_cost="0.03"
    
    # CloudWatch Logs (estimate 500MB/month)
    local cw_cost="0.25"
    
    # Secrets Manager
    local secrets_cost="0.40"
    
    local total_other=$(echo "scale=2; $s3_cost + $cw_cost + $secrets_cost" | bc)
    
    echo "  S3 Storage (~1GB):     \$${s3_cost}"
    echo "  CloudWatch Logs:       \$${cw_cost}"
    echo "  Secrets Manager:       \$${secrets_cost}"
    echo -e "  ${GREEN}Total Other:          \$${total_other}${NC}"
    
    OTHER_TOTAL="$total_other"
}

# ═══════════════════════════════════════════════════════════════════════════════
# COST EXPLORER API (Actual Costs)
# ═══════════════════════════════════════════════════════════════════════════════

get_actual_costs() {
    print_section "Actual AWS Costs (Last 30 Days)"
    
    local end_date=$(date +%Y-%m-%d)
    local start_date=$(date -d "30 days ago" +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d)
    
    echo "  Period: $start_date to $end_date"
    echo ""
    
    # Get costs by service
    aws ce get-cost-and-usage \
        --time-period Start="$start_date",End="$end_date" \
        --granularity MONTHLY \
        --metrics "UnblendedCost" \
        --group-by Type=DIMENSION,Key=SERVICE \
        --filter '{
            "Tags": {
                "Key": "Project",
                "Values": ["3-Tier-Web-Application"]
            }
        }' \
        --query 'ResultsByTime[0].Groups[*].{
            Service: Keys[0],
            Cost: Metrics.UnblendedCost.Amount
        }' \
        --output table 2>/dev/null || {
            echo -e "  ${YELLOW}Cost Explorer data not available (requires deployed resources)${NC}"
            echo "  Run 'terraform apply' and wait 24h for cost data to appear"
        }
}

# ═══════════════════════════════════════════════════════════════════════════════
# COST FORECAST
# ═══════════════════════════════════════════════════════════════════════════════

get_cost_forecast() {
    print_section "30-Day Cost Forecast"
    
    local start_date=$(date +%Y-%m-%d)
    local end_date=$(date -d "30 days" +%Y-%m-%d 2>/dev/null || date -v+30d +%Y-%m-%d)
    
    aws ce get-cost-forecast \
        --time-period Start="$start_date",End="$end_date" \
        --granularity MONTHLY \
        --metric "UNBLENDED_COST" \
        --filter '{
            "Tags": {
                "Key": "Project",
                "Values": ["3-Tier-Web-Application"]
            }
        }' \
        --query '{
            ForecastedCost: Total.Amount,
            Currency: Total.Unit,
            LowerBound: ForecastResultsByTime[0].MeanValue,
            UpperBound: ForecastResultsByTime[0].MeanValue
        }' \
        --output table 2>/dev/null || {
            echo -e "  ${YELLOW}Forecast not available (requires historical data)${NC}"
        }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY & RECOMMENDATIONS
# ═══════════════════════════════════════════════════════════════════════════════

print_summary() {
    print_header "COST SUMMARY"
    
    local total=$(echo "scale=2; ${EC2_TOTAL:-15} + ${RDS_TOTAL:-15} + ${NAT_TOTAL:-65} + ${ALB_TOTAL:-20} + ${VPC_ENDPOINT_TOTAL:-22} + ${OTHER_TOTAL:-1}" | bc)
    
    echo "  ┌────────────────────────────────────────┐"
    echo "  │ Service                    Monthly     │"
    echo "  ├────────────────────────────────────────┤"
    printf "  │ EC2 Instances              \$%-8s │\n" "${EC2_TOTAL:-15.18}"
    printf "  │ RDS Database               \$%-8s │\n" "${RDS_TOTAL:-14.64}"
    printf "  │ NAT Gateways               \$%-8s │\n" "${NAT_TOTAL:-64.80}"
    printf "  │ Application Load Balancer  \$%-8s │\n" "${ALB_TOTAL:-20.00}"
    printf "  │ VPC Endpoints              \$%-8s │\n" "${VPC_ENDPOINT_TOTAL:-21.60}"
    printf "  │ Other (S3, CW, Secrets)    \$%-8s │\n" "${OTHER_TOTAL:-0.68}"
    echo "  ├────────────────────────────────────────┤"
    printf "  │ ${GREEN}TOTAL ESTIMATED MONTHLY     \$%-8s${NC} │\n" "$total"
    echo "  └────────────────────────────────────────┘"
    
    TOTAL_MONTHLY="$total"
}

print_recommendations() {
    print_header "COST OPTIMIZATION RECOMMENDATIONS"
    
    echo "  1. ${YELLOW}Disable NAT Gateways${NC} (biggest savings)"
    echo "     Set enable_nat_gateway=false in terraform.tfvars"
    echo "     Savings: ~\$65/month"
    echo ""
    echo "  2. ${YELLOW}Use Spot Instances${NC} for non-production"
    echo "     Up to 90% savings on EC2 costs"
    echo "     Savings: ~\$10/month"
    echo ""
    echo "  3. ${YELLOW}Right-size RDS${NC}"
    echo "     db.t3.micro is good for dev/demo"
    echo "     Consider Aurora Serverless for variable workloads"
    echo ""
    echo "  4. ${YELLOW}Use Reserved Instances${NC} for production"
    echo "     1-year commitment: 30-40% savings"
    echo "     3-year commitment: up to 60% savings"
    echo ""
    echo "  5. ${YELLOW}Review VPC Endpoints${NC}"
    echo "     Each interface endpoint costs \$7.20/month"
    echo "     Only enable what you need"
}

print_free_tier_note() {
    print_section "AWS Free Tier Notes"
    
    echo "  If within first 12 months of AWS account:"
    echo "  - EC2 t2.micro/t3.micro: 750 hours FREE"
    echo "  - RDS db.t2.micro: 750 hours FREE"
    echo "  - S3: 5GB storage FREE"
    echo "  - CloudWatch: Basic monitoring FREE"
    echo ""
    echo -e "  ${GREEN}Potential Free Tier Savings: ~\$30/month${NC}"
    echo ""
    echo -e "  ${RED}NOT included in Free Tier:${NC}"
    echo "  - NAT Gateways"
    echo "  - Application Load Balancer"
    echo "  - VPC Endpoints (Interface type)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    print_header "AWS Cost Analysis - ${PROJECT_NAME}"
    
    echo "  Analyzing infrastructure costs..."
    echo "  Region: ${AWS_REGION:-us-east-1}"
    echo "  Date: $(date)"
    
    # Calculate estimated costs
    get_ec2_costs
    get_rds_costs
    get_nat_gateway_costs
    get_alb_costs
    get_vpc_endpoint_costs
    get_other_costs
    
    # Print summary
    print_summary
    
    # Get actual costs if available
    if [[ "$DETAILED" == "true" ]]; then
        get_actual_costs
    fi
    
    # Get forecast if requested
    if [[ "$FORECAST" == "true" ]]; then
        get_cost_forecast
    fi
    
    # Recommendations
    print_recommendations
    print_free_tier_note
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  Analysis complete. Total estimated monthly cost: \$${TOTAL_MONTHLY:-115}"
    echo "═══════════════════════════════════════════════════════════════════"
}

main

