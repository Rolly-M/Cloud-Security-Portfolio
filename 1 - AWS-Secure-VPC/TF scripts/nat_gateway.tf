# nat_gateway.tf

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  
  tags = {
    Name = "${var.environment}-nat-eip"
  }
  
  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway in first public subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  
  tags = {
    Name = "${var.environment}-nat-gateway"
  }
  
  depends_on = [aws_internet_gateway.main]
}