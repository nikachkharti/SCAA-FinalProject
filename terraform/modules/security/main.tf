# A security group is a stateful firewall attached to the EC2 instance.
resource "aws_security_group" "web" {
  name        = "${var.name_prefix}-web-sg"
  description = "Allow inbound HTTP only. No SSH - deployment uses AWS SSM."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-web-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---- INBOUND -------------------------------------------------------------
# Only one rule: the web port. Port 22 (SSH) stays CLOSED on purpose.
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP access to the web application"
  cidr_ipv4         = var.allowed_http_cidr
  from_port         = var.host_port
  to_port           = var.host_port
  ip_protocol       = "tcp"
}

# ---- OUTBOUND ------------------------------------------------------------
# The instance must reach ECR, CloudWatch and SSM over HTTPS.
resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS out - ECR, CloudWatch, SSM, package updates"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "http_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP out - Amazon Linux package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}