# Terraform configuration is in versions.tf
# Optional: Uncomment to use remote state in versions.tf

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "3-Tier-Web-Application"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# NETWORKING LAYER
# ═══════════════════════════════════════════════════════════════════════════════

# VPC Module - Creates the network foundation
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2) # Limit to 2 AZs for cost
  enable_nat_gateway   = var.enable_nat_gateway
  enable_vpc_flow_logs = true
}

# VPC Endpoints - Private connectivity to AWS services (no internet required)
module "vpc_endpoints" {
  source = "./modules/vpc-endpoints"

  project_name            = var.project_name
  vpc_id                  = module.vpc.vpc_id
  vpc_cidr                = var.vpc_cidr
  region                  = var.aws_region
  private_subnet_ids      = module.vpc.private_subnet_ids
  private_route_table_ids = module.vpc.private_route_table_ids

  # Enable endpoints for secure AWS service access
  enable_ssm_endpoint        = var.enable_ssm_endpoints  # Session Manager (no SSH needed!)
  enable_cloudwatch_endpoint = true
  enable_secrets_endpoint    = true
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY LAYER
# ═══════════════════════════════════════════════════════════════════════════════

# Security Groups Module - Implements Security Group Chaining
# ALB → App → RDS (traffic flows only through defined paths)
module "security_groups" {
  source = "./modules/security-groups"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
}

# ═══════════════════════════════════════════════════════════════════════════════
# STORAGE LAYER
# ═══════════════════════════════════════════════════════════════════════════════

# S3 Bucket Module - Encrypted storage for assets and logs
module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
}

# ═══════════════════════════════════════════════════════════════════════════════
# DATA LAYER (Isolated Network - No Internet Access)
# ═══════════════════════════════════════════════════════════════════════════════

# RDS Module - PostgreSQL in isolated subnets
module "rds" {
  source = "./modules/rds"

  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  # Use isolated database subnets (no NAT route) for security
  private_subnet_ids     = module.vpc.database_subnet_ids
  db_security_group_id   = module.security_groups.rds_security_group_id
  db_instance_class      = var.db_instance_class
  db_allocated_storage   = var.db_allocated_storage
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
}

# ═══════════════════════════════════════════════════════════════════════════════
# PRESENTATION LAYER (Public-Facing)
# ═══════════════════════════════════════════════════════════════════════════════

# Application Load Balancer Module
module "alb" {
  source = "./modules/alb"

  project_name          = var.project_name
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
  certificate_arn       = var.certificate_arn
  alb_logs_bucket_name  = module.s3.alb_logs_bucket_name
}

# ═══════════════════════════════════════════════════════════════════════════════
# APPLICATION LAYER (Private Subnets with NAT Access)
# ═══════════════════════════════════════════════════════════════════════════════

# Auto Scaling Group Module - EC2 instances running Flask application
module "asg" {
  source = "./modules/asg"

  project_name          = var.project_name
  environment           = var.environment
  ami_id                = data.aws_ami.amazon_linux.id
  instance_type         = var.instance_type
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids  # Application layer subnets
  app_security_group_id = module.security_groups.app_security_group_id
  target_group_arn      = module.alb.target_group_arn
  min_size              = var.asg_min_size
  max_size              = var.asg_max_size
  desired_capacity      = var.asg_desired_capacity
  db_endpoint           = module.rds.db_endpoint
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  s3_bucket_name        = module.s3.bucket_name
}

# ═══════════════════════════════════════════════════════════════════════════════
# MONITORING & OBSERVABILITY
# ═══════════════════════════════════════════════════════════════════════════════

# CloudWatch Alarms Module - Proactive monitoring and alerting
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name     = var.project_name
  alb_arn_suffix   = module.alb.alb_arn_suffix
  asg_name         = module.asg.asg_name
  target_group_arn = module.alb.target_group_arn
  region           = var.aws_region
}

# ═══════════════════════════════════════════════════════════════════════════════
# COMPLIANCE & GOVERNANCE
# ═══════════════════════════════════════════════════════════════════════════════

# AWS Config Module - Continuous compliance monitoring
module "aws_config" {
  source = "./modules/aws-config"

  project_name = var.project_name
  environment  = var.environment
}

