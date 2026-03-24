# bastion.tf

# ============================================
# BASTION HOST EC2 INSTANCE
# ============================================

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.bastion_instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }
  
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y htop
              
              # Enable logging of all commands
              echo 'export PROMPT_COMMAND="history -a"' >> /etc/profile
              echo 'export HISTTIMEFORMAT="%F %T "' >> /etc/profile
              
              # Security hardening
              sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
              systemctl restart sshd
              EOF
  
  tags = {
    Name = "${var.environment}-bastion-host"
    Role = "Bastion"
  }
}

# Elastic IP for Bastion (static IP)
resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
  
  tags = {
    Name = "${var.environment}-bastion-eip"
  }
}