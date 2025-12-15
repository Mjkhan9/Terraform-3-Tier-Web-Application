output "config_recorder_id" {
  description = "AWS Config Recorder ID"
  value       = aws_config_configuration_recorder.main.id
}

output "config_bucket_name" {
  description = "S3 bucket name for Config delivery"
  value       = aws_s3_bucket.config.bucket
}

output "config_rules" {
  description = "List of Config rule names"
  value = [
    aws_config_config_rule.ec2_detailed_monitoring.name,
    aws_config_config_rule.rds_encryption.name,
    aws_config_config_rule.restricted_ssh.name,
    aws_config_config_rule.s3_encryption.name,
    aws_config_config_rule.vpc_flow_logs.name,
    aws_config_config_rule.rds_multi_az.name,
    aws_config_config_rule.required_tags.name,
    aws_config_config_rule.ebs_encryption.name,
    aws_config_config_rule.alb_waf.name,
    aws_config_config_rule.cloudtrail_enabled.name
  ]
}

