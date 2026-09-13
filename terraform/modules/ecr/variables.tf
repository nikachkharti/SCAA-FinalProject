variable "repository_name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "keep_last_images" {
  description = "How many images to keep. Older ones are deleted automatically."
  type        = number
  default     = 5
}