output "secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "secret_name" {
  description = "Name of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "db_password" {
  description = "Generated database password (sensitive)"
  value       = random_password.db_password.result
  sensitive   = true
}

output "read_secret_policy_arn" {
  description = "ARN of the IAM policy to read the secret"
  value       = aws_iam_policy.read_db_secret.arn
}

