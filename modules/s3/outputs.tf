output "bucket_name" {
  description = "S3 bucket name for assets"
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "S3 bucket ARN for assets"
  value       = aws_s3_bucket.assets.arn
}

output "alb_logs_bucket_name" {
  description = "S3 bucket name for ALB logs"
  value       = aws_s3_bucket.alb_logs.id
}

