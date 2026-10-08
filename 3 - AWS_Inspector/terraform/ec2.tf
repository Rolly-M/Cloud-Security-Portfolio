###############################################################################
# EC2 Test Instances for Inspector v2 Scanning
#
# If var.vpc_id is provided the instances are placed in the caller-supplied
# subnets.  Otherwise a minimal standalone VPC is created so this project
# can be deployed independently.
###############################################################################

# ---------------------------------------------------------------------------
# Standalone VPC (used only when var.vpc_id == "")
# ---------------------------------------------------------------------------

resource "aws_vpc" "standalone" {
  count = var.vpc_id == "" ? 1 : 0

  cidr_block           = "10.3.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "standalone_private_a" {
  count = var.vpc_id == "" ? 1 : 0

  vpc_id            = aws_vpc.standalone[0].id
  cidr_block        = "10.3.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${local.name_prefix}-private-a"
  }
}

resource "aws_subnet" "standalone_private_b" {
  count = var.vpc_id == "" ? 1 : 0

  vpc_id            = aws_vpc.standalone[0].id
  cidr_block        = "10.3.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${local.name_prefix}-private-b"
  }
}

# VPC Endpoint for SSM (required so instances in private subnets can reach SSM
# without a NAT gateway, keeping costs low)
resource "aws_vpc_endpoint" "ssm" {
  count = var.vpc_id == "" ? 1 : 0

  vpc_id              = aws_vpc.standalone[0].id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.standalone_private_a[0].id, aws_subnet.standalone_private_b[0].id]
  security_group_ids  = [aws_security_group.test_instances.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count = var.vpc_id == "" ? 1 : 0

  vpc_id              = aws_vpc.standalone[0].id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.standalone_private_a[0].id, aws_subnet.standalone_private_b[0].id]
  security_group_ids  = [aws_security_group.test_instances.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  count = var.vpc_id == "" ? 1 : 0

  vpc_id              = aws_vpc.standalone[0].id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.standalone_private_a[0].id, aws_subnet.standalone_private_b[0].id]
  security_group_ids  = [aws_security_group.test_instances.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-ec2messages-endpoint"
  }
}

# ---------------------------------------------------------------------------
# Resolved VPC / subnet references (works for both modes)
# ---------------------------------------------------------------------------

locals {
  resolved_vpc_id = var.vpc_id != "" ? var.vpc_id : aws_vpc.standalone[0].id

  resolved_subnet_ids = (
    var.vpc_id != "" && length(var.subnet_ids) > 0
    ? var.subnet_ids
    : [
        aws_subnet.standalone_private_a[0].id,
        aws_subnet.standalone_private_b[0].id,
      ]
  )
}

# ---------------------------------------------------------------------------
# Security Group — no inbound SSH; outbound to VPC endpoints only
# ---------------------------------------------------------------------------

resource "aws_security_group" "test_instances" {
  name        = "${local.name_prefix}-test-instances-sg"
  description = "Security group for Inspector test instances — SSM access, no inbound SSH"
  vpc_id      = local.resolved_vpc_id

  # Allow HTTPS outbound to VPC endpoints (SSM, SSMMessages, EC2Messages)
  egress {
    description = "HTTPS to VPC endpoints for SSM Agent"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-test-instances-sg"
  }
}

# ---------------------------------------------------------------------------
# IAM — EC2 Instance Profile with SSM + Inspector permissions
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ec2_inspector" {
  name = "${local.name_prefix}-ec2-inspector-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-ec2-inspector-role"
  }
}

# SSM managed policy — required for SSM Agent and Inspector v2 agent communication
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_inspector.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Inspector v2 sends findings via the SSM channel — no extra policy needed
# beyond AmazonSSMManagedInstanceCore for the agent itself

resource "aws_iam_instance_profile" "ec2_inspector" {
  name = "${local.name_prefix}-ec2-inspector-profile"
  role = aws_iam_role.ec2_inspector.name
}

# ---------------------------------------------------------------------------
# EC2 Test Instances (t3.micro — free-tier eligible)
# ---------------------------------------------------------------------------

resource "aws_instance" "test_instance_a" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.micro"
  subnet_id              = local.resolved_subnet_ids[0]
  iam_instance_profile   = aws_iam_instance_profile.ec2_inspector.name
  vpc_security_group_ids = [aws_security_group.test_instances.id]

  # No key pair — access exclusively via SSM Session Manager
  associate_public_ip_address = false

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  tags = {
    Name        = "${local.name_prefix}-test-instance-a"
    InspectorScan = "enabled"
  }
}

resource "aws_instance" "test_instance_b" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.micro"
  subnet_id              = local.resolved_subnet_ids[length(local.resolved_subnet_ids) > 1 ? 1 : 0]
  iam_instance_profile   = aws_iam_instance_profile.ec2_inspector.name
  vpc_security_group_ids = [aws_security_group.test_instances.id]

  associate_public_ip_address = false

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  tags = {
    Name          = "${local.name_prefix}-test-instance-b"
    InspectorScan = "enabled"
  }
}

# ---------------------------------------------------------------------------
# SSM Association — install / activate the Amazon Inspector SSM plugin
# ---------------------------------------------------------------------------

resource "aws_ssm_association" "inspector_plugin" {
  name = "AmazonInspector2-ConfigureInspectorSsmPlugin"

  targets {
    key    = "tag:InspectorScan"
    values = ["enabled"]
  }

  parameters = {
    Operation = "Install"
  }
}
