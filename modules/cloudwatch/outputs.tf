output "sns_topic_arn" {
  description = "SNS Topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}

