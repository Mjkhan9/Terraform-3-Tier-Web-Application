output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = module.alb.alb_zone_id
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 bucket name for assets"
  value       = module.s3.bucket_name
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = module.s3.bucket_arn
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.asg.asg_name
}

output "application_url" {
  description = "URL to access the web application"
  value       = "http://${module.alb.alb_dns_name}"
}

output "instructions" {
  description = "Instructions for accessing the application"
  value       = <<-EOT
    ============================================
    🚀 3-Tier Web Application Deployed!
    ============================================
    
    Application URL: http://${module.alb.alb_dns_name}
    
    Database Endpoint: ${module.rds.db_endpoint}
    S3 Bucket: ${module.s3.bucket_name}
    
    Note: The application may take a few minutes to become available
    as EC2 instances launch and the application initializes.
    
    To view logs:
    - CloudWatch Logs: /aws/ec2/${var.project_name}
    - ALB Access Logs: Check S3 bucket ${module.s3.bucket_name}/alb-logs/
    
    ============================================
  EOT
}

