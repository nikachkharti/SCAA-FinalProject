variable "name_prefix" {
  type        = string
  description = "Prefix for resource names."
}

variable "aws_region" {
  type        = string
  description = "Region - needed inside the user data script."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type."
}

variable "root_volume_size" {
  type        = number
  description = "Root disk size in GB."
}

variable "subnet_id" {
  type        = string
  description = "Subnet to launch into."
}

variable "security_group_id" {
  type        = string
  description = "Security group to attach."
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile name."
}

variable "ecr_repository_url" {
  type        = string
  description = "ECR repository URL to pull the image from."
}

variable "image_tag" {
  type        = string
  description = "Image tag to run."
}

variable "container_name" {
  type        = string
  description = "Name of the running container."
}

variable "container_port" {
  type        = number
  description = "Port inside the container."
}

variable "host_port" {
  type        = number
  description = "Port on the instance."
}

variable "application_log_group" {
  type        = string
  description = "CloudWatch log group for container logs."
}

variable "system_log_group" {
  type        = string
  description = "CloudWatch log group for OS logs."
}

variable "metrics_namespace" {
  type        = string
  description = "CloudWatch namespace for custom metrics."
}
