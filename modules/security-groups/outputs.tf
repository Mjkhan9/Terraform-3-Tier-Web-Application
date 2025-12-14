output "alb_security_group_id" {
  description = "ALB Security Group ID"
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Application Security Group ID"
  value       = aws_security_group.app.id
}

output "rds_security_group_id" {
  description = "RDS Security Group ID"
  value       = aws_security_group.rds.id
}

