output "repository_url" {
  description = "Full URL used by docker push / docker pull."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN, used to give the EC2 role pull-only access to THIS repo."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "AWS account ID that owns the registry."
  value       = aws_ecr_repository.this.registry_id
}