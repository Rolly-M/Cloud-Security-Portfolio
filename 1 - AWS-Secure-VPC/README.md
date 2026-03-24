# 🔒 AWS Secure VPC (CIS Baseline Lab - Week 1)

[![Terraform](https://img.shields.io/badge/Terraform-v1.5-blue?style=for-the-badge&logo=terraform)](https://www.terraform.io/)
[![AWS Free Tier](https://img.shields.io/badge/AWS-Free%20Tier-green?style=for-the-badge&logo=amazon-aws)](https://aws.amazon.com/free/)
[![SCS-C01 Domain 1](https://img.shields.io/badge/SCS-C01%20Dom1-yellow?style=for-the-badge&logo=amazon-aws)](https://aws.amazon.com/security/specialty/)
[![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/yourusername/AWS-Secure-VPC/security-scan.yml)](https://github.com/yourusername/AWS-Secure-VPC/actions)

**Lab Goal**: Build CIS-compliant VPC with NACLs, Flow Logs. Refresh AWS SA + Test breaches. **Compliance: 100%**.

┌─────────────────────────────────────────────────────────────────┐
│                           INTERNET                              │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         VPC (10.0.0.0/16)                       │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    PUBLIC SUBNETS                          │ │
│  │  ┌─────────────────┐                                       │ │
│  │  │  BASTION HOST   │◄── SSH (Port 22) from YOUR IP ONLY    │ │
│  │  │  10.0.1.x       │                                       │ │
│  │  └────────┬────────┘                                       │ │
│  └───────────┼────────────────────────────────────────────────┘ │
│              │ SSH (Port 22)                                    │
│              ▼                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    PRIVATE SUBNETS                         │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │ │
│  │  │ Web Server  │  │  Database   │  │ App Server  │         │ │
│  │  │ 10.0.101.x  │  │ 10.0.102.x  │  │ 10.0.103.x  │         │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘         │ │
│  │                                                            │ │
│  │  ✗ NO direct internet access                               │ │
│  │  ✗ NO direct SSH from outside                              │ │
│  │  ✓ Only accessible via Bastion Host                        │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

## 🎯 Prerequisites
- AWS Free Tier Account.
- Terraform CLI + AWS CLI (`aws configure`).
- Git.

## 🚀 Step-by-Step Deployment
1. **Clone & Init**: `git clone https://github.com/yourusername/AWS-Secure-VPC.git && cd AWS-Secure-VPC && terraform init`.
2. **Review Config**: Edit `main.tf` (CIDR: 10.0.0.0/16, 3 subnets).
3. **Apply**: `terraform plan && terraform apply --auto-approve`.
4. **Test Breaches**: 
   - Launch bastion EC2 (SSM).
   - `nmap -p 22,80 <bastion-ip>` → Denied by NACL.
5. **Verify Flow Logs**: AWS Console > VPC > Flow Logs → CloudWatch.
6. **Destroy**: `terraform destroy --auto-approve`.

**Time**: 45min | Cost: ~\$0.

## 📁 Files
- `main.tf`: VPC + NACLs + Flow Logs.
- `outputs.tf`: VPC ID, Subnets.
- `demos/breach-test.png`: NACL deny proof.

## 🎬 Demo
![Demo GIF](demos/vpc-demo.gif) *(Record via Peek/Loom)*

**Screenshots**:
![Flow Logs](screenshots/flow-logs.png)

## 🔗 Links
- **Live Demo**: [AWS Console VPC](https://us-east-1.console.aws.amazon.com/vpc/home)
- **Full Portfolio**: [CloudSec-Portfolio](https://github.com/yourusername/CloudSec-Portfolio)

**Fork/Star & Deploy! #AWSSecurity** ⭐
*Week 1 SCS Prep | Last Update: [Date]*