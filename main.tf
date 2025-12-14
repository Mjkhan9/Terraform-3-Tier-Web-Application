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

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name     = var.project_name
  environment      = var.environment
  vpc_cidr         = var.vpc_cidr
  availability_zones = data.aws_availability_zones.available.names
  enable_nat_gateway = true
  enable_vpc_flow_logs = true
}

# Security Groups Module
module "security_groups" {
  source = "./modules/security-groups"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
}

# S3 Bucket Module
module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
}

# RDS Module
module "rds" {
  source = "./modules/rds"

  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  db_security_group_id   = module.security_groups.rds_security_group_id
  db_instance_class      = var.db_instance_class
  db_allocated_storage   = var.db_allocated_storage
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
}

# Application Load Balancer Module
module "alb" {
  source = "./modules/alb"

  project_name        = var.project_name
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
  certificate_arn     = var.certificate_arn
  alb_logs_bucket_name = module.s3.alb_logs_bucket_name
}

# Auto Scaling Group Module
module "asg" {
  source = "./modules/asg"

  project_name              = var.project_name
  environment               = var.environment
  ami_id                    = data.aws_ami.amazon_linux.id
  instance_type             = var.instance_type
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  app_security_group_id     = module.security_groups.app_security_group_id
  target_group_arn          = module.alb.target_group_arn
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  db_endpoint               = module.rds.db_endpoint
  db_name                   = var.db_name
  db_username               = var.db_username
  db_password               = var.db_password
  s3_bucket_name            = module.s3.bucket_name
}

# CloudWatch Alarms Module
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name     = var.project_name
  alb_arn_suffix   = module.alb.alb_arn_suffix
  asg_name         = module.asg.asg_name
  target_group_arn = module.alb.target_group_arn
}

