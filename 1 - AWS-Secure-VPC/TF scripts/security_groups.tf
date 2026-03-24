# security_groups.tf

# ============================================
# BASTION HOST SECURITY GROUP
# ============================================

resource "aws_security_group" "bastion" {
  name        = "${var.environment}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id
  
  # Inbound SSH from allowed CIDR only
  ingress {
    description = "SSH from allowed IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }
  
  # Outbound to anywhere
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.environment}-bastion-sg"
  }
}

# ============================================
# PRIVATE INSTANCES SECURITY GROUP
# ============================================

resource "aws_security_group" "private_instances" {
  name        = "${var.environment}-private-instances-sg"
  description = "Security group for private instances"
  vpc_id      = aws_vpc.main.id
  
  # Allow SSH ONLY from Bastion security group
  ingress {
    description     = "SSH from Bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  
  # Allow HTTP from within VPC
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  # Allow HTTPS from within VPC
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  # Outbound to anywhere (for updates)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.environment}-private-instances-sg"
  }
}