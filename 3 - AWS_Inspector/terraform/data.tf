###############################################################################
# Data Sources
###############################################################################

# Current AWS Account
data "aws_caller_identity" "current" {}

# Current AWS Region
data "aws_region" "current" {}

# Look up existing VPC by tag when var.vpc_id is provided
data "aws_vpc" "existing" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

# Latest Amazon Linux 2 AMI (required for SSM Agent pre-installed)
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
