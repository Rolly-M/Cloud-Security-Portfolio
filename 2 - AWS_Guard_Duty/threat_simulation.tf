# threat_simulation.tf - Resources for Testing GuardDuty Detection

# ==========================================
# THREAT SIMULATION INSTANCE
# ==========================================
resource "aws_instance" "threat_simulation" {
  count                  = var.enable_guardduty && var.enable_threat_simulation ? 1 : 0
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.micro"
  key_name               = var.key_name
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.private_instances.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y nmap curl wget
              
              # Create simulation scripts directory
              mkdir -p /home/ec2-user/threat-simulation
              
              # Script: Simulate DNS query to known bad domain
              cat > /home/ec2-user/threat-simulation/dns_exfil_test.sh << 'SCRIPT'
              #!/bin/bash
              # This simulates DNS-based data exfiltration
              # GuardDuty monitors DNS queries for suspicious patterns
              echo "Testing DNS query to GuardDuty test domain..."
              dig guarddutyc2activityb.com
              nslookup guarddutyc2activityb.com
              SCRIPT
              
              # Script: Simulate cryptocurrency mining DNS
              cat > /home/ec2-user/threat-simulation/crypto_test.sh << 'SCRIPT'
              #!/bin/bash
              # This simulates crypto mining pool DNS queries
              echo "Testing crypto mining domain detection..."
              dig pool.minergate.com
              dig xmr.pool.minergate.com
              SCRIPT
              
              # Script: Simulate port scanning
              cat > /home/ec2-user/threat-simulation/port_scan_test.sh << 'SCRIPT'
              #!/bin/bash
              # This simulates reconnaissance activity
              echo "Testing port scan detection..."
              nmap -sT -p 22,80,443,3389 10.0.0.0/24 --max-retries 0 --max-rate 10
              SCRIPT
              
              # Script: Use GuardDuty tester
              cat > /home/ec2-user/threat-simulation/guardduty_tester.sh << 'SCRIPT'
              #!/bin/bash
              # Official AWS GuardDuty tester
              echo "Running GuardDuty sample findings generator..."
              
              # Install if not present
              if ! command -v guardduty_tester.py &> /dev/null; then
                  pip3 install --user boto3
                  wget -O /home/ec2-user/guardduty_tester.py https://raw.githubusercontent.com/awslabs/amazon-guardduty-tester/master/guardduty_tester.py
              fi
              
              python3 /home/ec2-user/guardduty_tester.py
              SCRIPT
              
              chmod +x /home/ec2-user/threat-simulation/*.sh
              chown -R ec2-user:ec2-user /home/ec2-user/threat-simulation
              
              echo "Threat simulation instance ready!"
              EOF

  tags = {
    Name        = "${var.environment}-threat-simulation"
    Environment = var.environment
    Purpose     = "GuardDuty Testing"
    Warning     = "TEST INSTANCE ONLY"
  }
}

# ==========================================
# GENERATE SAMPLE FINDINGS (AWS CLI METHOD)
# ==========================================
resource "null_resource" "generate_sample_findings" {
  count = var.enable_guardduty && var.enable_threat_simulation ? 1 : 0

  triggers = {
    detector_id = aws_guardduty_detector.main[0].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Generating GuardDuty sample findings..."
      aws guardduty create-sample-findings \
        --detector-id ${aws_guardduty_detector.main[0].id} \
        --finding-types \
          "Backdoor:EC2/C&CActivity.B" \
          "CryptoCurrency:EC2/BitcoinTool.B!DNS" \
          "Trojan:EC2/BlackholeTraffic" \
          "UnauthorizedAccess:EC2/SSHBruteForce" \
          "