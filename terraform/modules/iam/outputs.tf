output "instance_profile_name" {
  description = "Instance profile to attach to the EC2 instance."
  value       = aws_iam_instance_profile.instance.name
}

output "role_arn" {
  description = "ARN of the EC2 role."
  value       = aws_iam_role.instance.arn
}

output "role_name" {
  description = "Name of the EC2 role."
  value       = aws_iam_role.instance.name
}