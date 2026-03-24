# nacls.tf

# ============================================
# PUBLIC SUBNET NACL (For Bastion Host)
# ============================================

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id
  
  tags = {
    Name = "${var.environment}-public-nacl"
  }
}

# INBOUND RULES - Public NACL

# Allow SSH (22) from allowed CIDR only (your IP)
resource "aws_network_acl_rule" "public_inbound_ssh" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.allowed_ssh_cidr
  from_port      = 22
  to_port        = 22
}

# Allow HTTP (80) from anywhere (for web servers if needed)
resource "aws_network_acl_rule" "public_inbound_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

# Allow HTTPS (443) from anywhere
resource "aws_network_acl_rule" "public_inbound_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# Allow ephemeral ports (return traffic)
resource "aws_network_acl_rule" "public_inbound_ephemeral" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 140
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# OUTBOUND RULES - Public NACL

# Allow all outbound traffic
resource "aws_network_acl_rule" "public_outbound_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}


# ============================================
# PRIVATE SUBNET NACL
# ============================================

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id
  
  tags = {
    Name = "${var.environment}-private-nacl"
  }
}

# INBOUND RULES - Private NACL

# Allow SSH (22) ONLY from Bastion subnet (public subnet 1)
resource "aws_network_acl_rule" "private_inbound_ssh_bastion" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_cidrs[0]  # Bastion subnet only
  from_port      = 22
  to_port        = 22
}

# DENY SSH (22) from all other sources
resource "aws_network_acl_rule" "private_deny_ssh_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 105
  egress         = false
  protocol       = "tcp"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = 22
  to_port        = 22
}

# Allow HTTP (80) ONLY from within VPC
resource "aws_network_acl_rule" "private_inbound_http_vpc" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 80
  to_port        = 80
}

# DENY HTTP (80) from all other sources
resource "aws_network_acl_rule" "private_deny_http_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 115
  egress         = false
  protocol       = "tcp"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

# Allow HTTPS (443) from within VPC
resource "aws_network_acl_rule" "private_inbound_https_vpc" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 443
  to_port        = 443
}

# Allow ephemeral ports (return traffic from internet via NAT)
resource "aws_network_acl_rule" "private_inbound_ephemeral" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 140
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# OUTBOUND RULES - Private NACL

# Allow HTTP outbound (for updates via NAT)
resource "aws_network_acl_rule" "private_outbound_http" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

# Allow HTTPS outbound
resource "aws_network_acl_rule" "private_outbound_https" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# Allow ephemeral ports outbound (return traffic)
resource "aws_network_acl_rule" "private_outbound_ephemeral" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 140
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}