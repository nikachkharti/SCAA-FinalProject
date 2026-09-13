variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repo the instance may pull from."
  type        = string
}

variable "log_group_arns" {
  description = "ARNs of the CloudWatch log groups the instance may write to."
  type        = list(string)
}