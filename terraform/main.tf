# ---------------------------------------------------------------------------
# Look up the default VPC and its subnets.
# Using the default VPC keeps this project small. In a real company you would
# create your own VPC module with private subnets and a load balancer.
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix       = "${var.project_name}-${var.environment}"
  container_name    = "${var.project_name}-web"
  metrics_namespace = "${var.project_name}-${var.environment}/system"

  # Pick the first default subnet, sorted so the choice is stable.
  subnet_id = sort(data.aws_subnets.default.ids)[0]
}

# ------------------------------------------------------------- 1. Registry
module "ecr" {
  source = "./modules/ecr"

  repository_name  = local.name_prefix
  keep_last_images = 5
}

# ----------------------------------------------------------- 2. Monitoring
# Created before compute, because the log groups must exist before the
# container starts writing to them.
module "monitoring" {
  source = "./modules/monitoring"

  name_prefix       = local.name_prefix
  retention_in_days = var.log_retention_days
}

# ------------------------------------------------------------- 3. Firewall
module "security" {
  source = "./modules/security"

  name_prefix       = local.name_prefix
  vpc_id            = data.aws_vpc.default.id
  allowed_http_cidr = var.allowed_http_cidr
  host_port         = var.host_port
}

# ---------------------------------------------------------- 4. Permissions
module "iam" {
  source = "./modules/iam"

  name_prefix        = local.name_prefix
  ecr_repository_arn = module.ecr.repository_arn
  log_group_arns     = module.monitoring.log_group_arns
}

# -------------------------------------------------------------- 5. Compute
module "compute" {
  source = "./modules/compute"

  name_prefix      = local.name_prefix
  aws_region       = var.aws_region
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  subnet_id             = local.subnet_id
  security_group_id     = module.security.security_group_id
  instance_profile_name = module.iam.instance_profile_name

  ecr_repository_url = module.ecr.repository_url
  image_tag          = var.image_tag

  container_name = local.container_name
  container_port = var.container_port
  host_port      = var.host_port

  application_log_group = module.monitoring.application_log_group_name
  system_log_group      = module.monitoring.system_log_group_name
  metrics_namespace     = local.metrics_namespace

  depends_on = [module.monitoring, module.iam]
}

# ---------------------------------------------------------------------------
# 6. Alarm + dashboard
#
# These are defined here (not inside the monitoring module) because they need
# the instance ID, and the instance needs the log groups. Putting them in the
# module would create a circular dependency.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name_prefix}-high-cpu"
  alarm_description   = "Average CPU above ${var.cpu_alarm_threshold}% for 10 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = module.compute.instance_id
  }

  tags = {
    Name = "${local.name_prefix}-high-cpu"
  }
}

resource "aws_cloudwatch_metric_alarm" "instance_unhealthy" {
  alarm_name          = "${local.name_prefix}-status-check-failed"
  alarm_description   = "EC2 status check failed - the instance is unhealthy"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = module.compute.instance_id
  }

  tags = {
    Name = "${local.name_prefix}-status-check-failed"
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU utilisation (%)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", module.compute.instance_id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Memory and disk used (%)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            [local.metrics_namespace, "MemoryUsedPercent", "InstanceId", module.compute.instance_id],
            [local.metrics_namespace, "DiskUsedPercent", "InstanceId", module.compute.instance_id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Network traffic (bytes)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", module.compute.instance_id],
            ["AWS/EC2", "NetworkOut", "InstanceId", module.compute.instance_id]
          ]
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Latest application logs"
          region = var.aws_region
          query  = "SOURCE '${module.monitoring.application_log_group_name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          view   = "table"
        }
      }
    ]
  })
}