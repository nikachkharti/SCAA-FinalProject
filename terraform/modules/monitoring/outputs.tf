output "application_log_group_name" {
  value = aws_cloudwatch_log_group.application.name
}

output "system_log_group_name" {
  value = aws_cloudwatch_log_group.system.name
}

output "log_group_arns" {
  description = "Both log group ARNs - used by the IAM module."
  value = [
    aws_cloudwatch_log_group.application.arn,
    aws_cloudwatch_log_group.system.arn,
  ]
}