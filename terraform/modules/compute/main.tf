# Always get the newest Amazon Linux 2023 AMI instead of hard-coding an ID.
# Hard-coded AMI IDs are different in every region and become outdated.
data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name

  associate_public_ip_address = true
  monitoring                  = true # detailed CloudWatch monitoring (1-minute metrics)

  # Force IMDSv2. This blocks a common cloud attack (SSRF stealing credentials).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # 2 so Docker containers can still reach it
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.name_prefix}-root-volume"
    }
  }

  # When the script changes, replace the instance so the change really applies.
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region            = var.aws_region
    ecr_repository_url    = var.ecr_repository_url
    image_tag             = var.image_tag
    container_name        = var.container_name
    container_port        = var.container_port
    host_port             = var.host_port
    application_log_group = var.application_log_group
    system_log_group      = var.system_log_group
    metrics_namespace     = var.metrics_namespace
  })

  tags = {
    Name = "${var.name_prefix}-app-server"
    Role = "application"
  }

  lifecycle {
    # The AMI ID changes when Amazon publishes an update. Ignoring it stops
    # Terraform from destroying your server on every single pipeline run.
    ignore_changes = [ami]
  }
}

# A static public IP, so the address does not change when the instance restarts.
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name = "${var.name_prefix}-eip"
  }

  depends_on = [aws_instance.app]
}