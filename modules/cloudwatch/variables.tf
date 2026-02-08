variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix"
  type        = string
}

variable "asg_name" {
  description = "Auto Scaling Group name"
  type        = string
}

variable "target_group_arn" {
  description = "Target Group ARN"
  type        = string
}

variable "region" {
  description = "AWS region for CloudWatch dashboard"
  type        = string
  default     = "us-east-1"
}

