# ---------------------------------------------------------------------------
# The EC2 instance needs permissions, but we must NEVER put access keys on it.
# Instead we create a ROLE that the EC2 service is allowed to assume, and
# attach it through an INSTANCE PROFILE. AWS then gives the instance temporary
# credentials that rotate automatically.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-ec2-role"
  description        = "Role for the application EC2 instance"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# ---- 1. Pull images from OUR repository only ------------------------------
data "aws_iam_policy_document" "ecr_pull" {
  # GetAuthorizationToken cannot be limited to one repo - AWS requires "*".
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Pulling the actual layers IS limited to our single repository.
  statement {
    sid    = "EcrPullFromThisRepoOnly"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "ecr_pull" {
  name   = "${var.name_prefix}-ecr-pull"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.ecr_pull.json
}

# ---- 2. Write logs and metrics to CloudWatch ------------------------------
data "aws_iam_policy_document" "cloudwatch" {
  statement {
    sid    = "WriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    # Only our own log groups, not every log group in the account.
    resources = concat(var.log_group_arns, [for a in var.log_group_arns : "${a}:*"])
  }

  statement {
    sid    = "PublishCustomMetrics"
    effect = "Allow"
    # PutMetricData does not support resource-level permissions, so we limit it
    # by namespace with a condition instead.
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["${var.name_prefix}/system"]
    }
  }

  statement {
    sid       = "ReadOwnTags"
    effect    = "Allow"
    actions   = ["ec2:DescribeTags"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cloudwatch" {
  name   = "${var.name_prefix}-cloudwatch-write"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.cloudwatch.json
}

# ---- 3. Let the pipeline run commands without SSH -------------------------
# AmazonSSMManagedInstanceCore is the AWS managed policy that turns on
# Systems Manager. This is what replaces SSH keys.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---- The instance profile is the "wrapper" EC2 actually accepts -----------
resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.instance.name
}