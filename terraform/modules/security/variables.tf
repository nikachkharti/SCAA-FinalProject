variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC where the security group is created."
  type        = string
}

variable "allowed_http_cidr" {
  description = "CIDR allowed to reach the web port."
  type        = string
}

variable "host_port" {
  description = "Port opened on the instance."
  type        = number
}