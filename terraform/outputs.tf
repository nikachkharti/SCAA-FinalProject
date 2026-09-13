output "application_url" {
  description = "Open this in the browser."
  value       = "http://${module.compute.public_ip}"
}

output "health_check_url" {
  description = "Health endpoint used by the pipeline."
  value       = "http://${module.compute.public_ip}/health"
}

output "version_url" {
  description = "Shows which image tag is running."
  value       = "http://${module.compute.public_ip}/version"
}

output "public_ip" {
  description = "Static public IP (Elastic IP)."
  value       = module.compute.public_ip
}

output "public_dns" {
  description = "Public DNS name of the instance."
  value       = module.compute.public_dns
}

output "instance_id" {
  description = "EC2 instance ID - the deploy job sends the SSM command here."
  value       = module.compute.instance_id
}

output "ecr_repository_url" {
  description = "Where the pipeline pushes the Docker image."
  value       = module.ecr.repository_url
}

output "application_log_group" {
  description = "CloudWatch log group with the container logs."
  value       = module.monitoring.application_log_group_name
}

output "system_log_group" {
  description = "CloudWatch log group with the OS logs."
  value       = module.monitoring.system_log_group_name
}

output "cloudwatch_dashboard_url" {
  description = "Direct link to the CloudWatch dashboard."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "aws_account_id" {
  description = "Account the resources were created in."
  value       = data.aws_caller_identity.current.account_id
}