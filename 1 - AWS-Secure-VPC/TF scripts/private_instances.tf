# private_instances.tf

# ============================================
# PRIVATE EC2 INSTANCES (Web/App Servers)
# ============================================

resource "aws_instance" "private" {
  count                  = var.private_instance_count
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.private_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  vpc_security_group_ids = [aws_security_group.private_instances.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
    
    tags = {
      Name = "${var.environment}-private-instance-${count.index + 1}-root"
    }
  }
  
  user_data = <<-EOF
              #!/bin/bash
              
              # Update system
              yum update -y
              
              # Install useful packages
              yum install -y htop amazon-cloudwatch-agent httpd
              
              # Start Apache for testing
              systemctl start httpd
              systemctl enable httpd
              
              # Create simple test page
              echo "<h1>Private Instance ${count.index + 1}</h1>" > /var/www/html/index.html
              echo "<p>Hostname: $(hostname)</p>" >> /var/www/html/index.html
              echo "<p>Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)</p>" >> /var/www/html/index.html
              
              # Configure CloudWatch Agent
              cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
              {
                "agent": {
                  "metrics_collection_interval": 60,
                  "run_as_user": "root"
                },
                "metrics": {
                  "namespace": "${var.environment}/EC2",
                  "metrics_collected": {
                    "cpu": {
                      "measurement": [
                        "cpu_usage_idle",
                        "cpu_usage_user",
                        "cpu_usage_system"
                      ],
                      "metrics_collection_interval": 60,
                      "totalcpu": true
                    },
                    "disk": {
                      "measurement": [
                        "used_percent",
                        "inodes_free"
                      ],
                      "metrics_collection_interval": 60,
                      "resources": [
                        "/"
                      ]
                    },
                    "mem": {
                      "measurement": [
                        "mem_used_percent"
                      ],
                      "metrics_collection_interval": 60
                    }
                  }
                },
                "logs": {
                  "logs_collected": {
                    "files": {
                      "collect_list": [
                        {
                          "file_path": "/var/log/messages",
                          "log_group_name": "${var.environment}-system-logs",
                          "log_stream_name": "{instance_id}/messages"
                        },
                        {
                          "file_path": "/var/log/secure",
                          "log_group_name": "${var.environment}-security-logs",
                          "log_stream_name": "{instance_id}/secure"
                        },
                        {
                          "file_path": "/var/log/httpd/access_log",
                          "log_group_name": "${var.environment}-httpd-access-logs",
                          "log_stream_name": "{instance_id}/access"
                        },
                        {
                          "file_path": "/var/log/httpd/error_log",
                          "log_group_name": "${var.environment}-httpd-error-logs",
                          "log_stream_name": "{instance_id}/error"
                        }
                      ]
                    }
                  }
                }
              }
              CWCONFIG
              
              # Start CloudWatch Agent
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
              
              EOF
  
  tags = {
    Name        = "${var.environment}-private-instance-${count.index + 1}"
    Environment = var.environment
    Role        = "WebServer"
  }
}

# ============================================
# CLOUDWATCH LOG GROUPS FOR PRIVATE INSTANCES
# ============================================

resource "aws_cloudwatch_log_group" "system_logs" {
  name              = "${var.environment}-system-logs"
  retention_in_days = 30
  
  tags = {
    Name        = "${var.environment}-system-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "security_logs" {
  name              = "${var.environment}-security-logs"
  retention_in_days = 90
  
  tags = {
    Name        = "${var.environment}-security-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "httpd_access_logs" {
  name              = "${var.environment}-httpd-access-logs"
  retention_in_days = 30
  
  tags = {
    Name        = "${var.environment}-httpd-access-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "httpd_error_logs" {
  name              = "${var.environment}-httpd-error-logs"
  retention_in_days = 30
  
  tags = {
    Name        = "${var.environment}-httpd-error-logs"
    Environment = var.environment
  }
}