# Log group for the application container (Docker awslogs driver writes here).
resource "aws_cloudwatch_log_group" "application" {
  name              = "/${var.name_prefix}/application"
  retention_in_days = var.retention_in_days

  tags = {
    Name      = "${var.name_prefix}-application-logs"
    LogSource = "container"
  }
}

# Log group for the operating system (CloudWatch agent writes here).
resource "aws_cloudwatch_log_group" "system" {
  name              = "/${var.name_prefix}/system"
  retention_in_days = var.retention_in_days

  tags = {
    Name      = "${var.name_prefix}-system-logs"
    LogSource = "ec2-os"
  }
}