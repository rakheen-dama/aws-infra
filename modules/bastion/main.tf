# -----------------------------------------------------------------------------
# SSM Bastion — t4g.nano in a private subnet for DB client access
#
# No SSH key, no public IP, no inbound ports. Access is exclusively via SSM
# Session Manager port forwarding (requires the session-manager-plugin locally):
#
#   aws ssm start-session --target <instance-id> \
#     --document-name AWS-StartPortForwardingSessionToRemoteHost \
#     --parameters '{"host":["<rds-endpoint>"],"portNumber":["5432"],"localPortNumber":["15432"]}'
#
# Then point DBeaver/DataGrip/psql at localhost:15432.
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_iam_role" "bastion" {
  name = "${var.project}-${var.environment}-bastion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project}-${var.environment}-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_security_group" "bastion" {
  name        = "${var.project}-${var.environment}-sg-bastion"
  description = "SSM bastion - no ingress, egress to VPC services and SSM endpoints"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project}-${var.environment}-sg-bastion"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# No ingress rules at all — SSM sessions are outbound from the instance's
# perspective (agent polls SSM over 443 via the NAT gateway).
resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Ingress rules on the data-layer SGs, owned here so they exist only when the
# bastion does.
resource "aws_vpc_security_group_ingress_rule" "rds_from_bastion" {
  security_group_id            = var.rds_sg_id
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from SSM bastion"
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_bastion" {
  security_group_id            = var.redis_sg_id
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "Redis from SSM bastion"
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  associate_public_ip_address = false

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  # Pin the AMI once launched — don't replace the bastion every time
  # Amazon publishes a new AL2023 image.
  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-bastion"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
