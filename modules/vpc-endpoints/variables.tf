variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for interface endpoints"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "List of private route table IDs for gateway endpoints"
  type        = list(string)
}

variable "enable_ssm_endpoint" {
  description = "Enable SSM endpoints for Session Manager (no SSH needed)"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_endpoint" {
  description = "Enable CloudWatch Logs endpoint"
  type        = bool
  default     = true
}

variable "enable_secrets_endpoint" {
  description = "Enable Secrets Manager endpoint"
  type        = bool
  default     = true
}

