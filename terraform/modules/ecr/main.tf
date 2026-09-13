resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"

  # Lets `terraform destroy` delete the repository even when images are inside.
  # Without this the destroy job fails and you keep paying.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true # free vulnerability scan of every pushed image
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep storage small and cheap: delete old images automatically.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the newest ${var.keep_last_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}