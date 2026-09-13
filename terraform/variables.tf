variable "aws_region" {
  description = "AWS region where everything is created."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short name used as a prefix for every resource name."
  type        = string
  default     = "scaa-final"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be lowercase letters, digits and dashes (3-21 chars)."
  }
}

variable "environment" {
  description = "Environment name: dev, staging or prod."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Who owns this infrastructure (shown in tags)."
  type        = string
  default     = "Nikoloz Chkhartishvili"
}

variable "repository_url" {
  description = "Source repository, shown in tags."
  type        = string
  default     = "https://github.com/nikachkharti/SCAA-FinalProject.git"
}

# ---------------------------------------------------------------------- app
variable "container_port" {
  description = "Port the application listens on inside the container."
  type        = number
  default     = 8080
}

variable "host_port" {
  description = "Port opened on the EC2 instance. 80 lets you open the site without :port."
  type        = number
  default     = 80
}

variable "image_tag" {
  description = "Docker image tag to deploy. The pipeline passes the short commit SHA."
  type        = string
  default     = "latest"
}

# ----------------------------------------------------------------- compute
variable "instance_type" {
  description = "EC2 size. t3.micro is Free Tier eligible in most regions."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Size of the EC2 disk in GB."
  type        = number
  default     = 20
}

# ---------------------------------------------------------------- security
variable "allowed_http_cidr" {
  description = "Who may open the website. 0.0.0.0/0 = the whole internet (needed for grading)."
  type        = string
  default     = "0.0.0.0/0"
}

# -------------------------------------------------------------- monitoring
variable "log_retention_days" {
  description = "How many days CloudWatch keeps the logs. Short retention = low cost."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "Use a retention value that CloudWatch accepts."
  }
}

variable "cpu_alarm_threshold" {
  description = "Fire the CloudWatch alarm when average CPU goes above this percent."
  type        = number
  default     = 80
}