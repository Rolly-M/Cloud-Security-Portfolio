# Project 1 — AWS Secure VPC

[![Terraform](https://img.shields.io/badge/Terraform-≥1.0-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-VPC_/_EC2_/_CloudWatch-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/vpc/)

A production-hardened AWS network built entirely in Terraform. The architecture follows defense-in-depth: public and private subnets are separated at both the routing and firewall layers, access to private instances is gated through a bastion host, and all network traffic is logged with CloudWatch alarms watching for brute-force and port-scan patterns.

This project provides the VPC foundation that Project 2 (GuardDuty) deploys into.

---

## Architecture

<img width="531" height="977" alt="VPC Architecture Diagram" src="https://github.com/user-attachments/assets/d577c5bc-8ea8-4ba4-bb5b-8f32592e7fa5" />

---

## Design Decisions

### Why two firewall layers?

Security Groups and Network ACLs serve different purposes and complement each other:

- **NACLs** are stateless subnet-level rules. They catch traffic that a Security Group would never see — for example, a response packet arriving on an unexpected port, or traffic from an instance that bypassed its SG by changing its own network config. The private subnet NACL explicitly denies SSH (22) and HTTP (80) from any source except the VPC CIDR and bastion subnet.
- **Security Groups** are stateful and instance-level. The private SG uses Security Group referencing — it allows SSH only from the bastion's SG ID, not from a CIDR range. This means even if a new instance were launched into the public subnet, it could not SSH into private instances unless it was explicitly assigned the bastion SG.

### Why split VPC Flow Logs?

Two separate log groups — one for accepted traffic, one for rejected — makes security queries faster. A SOC analyst hunting for brute-force attempts can query the rejected-traffic log without scanning all accepted flows. CloudWatch metric filters on the rejected log drive the SSH brute-force and port-scan alarms.

### Why a bastion over a VPN or SSM?

For a portfolio project, a bastion is the most transparent demonstration of network segmentation and key management. SSH agent forwarding (`ssh -A`) means the private key never leaves the engineer's machine — it is not copied to the bastion. In production, Systems Manager Session Manager (no open ports) or a VPN would typically replace this.

---

## Infrastructure Components

### Networking

| Resource | Detail |
|---|---|
| VPC | `10.0.0.0/16`, DNS hostnames and resolution enabled |
| Public subnets (×3) | One per AZ; host the bastion and NAT Gateway |
| Private subnets (×3) | One per AZ; host application instances with no direct internet route |
| Internet Gateway | Outbound path for public subnet resources |
| NAT Gateway | Allows private instances to pull OS updates; blocks inbound connections |
| Route tables | Public table routes `0.0.0.0/0` → IGW; private table routes `0.0.0.0/0` → NAT |

### Security

| Resource | Detail |
|---|---|
| Public NACL | Allows SSH from admin IP only, HTTP/HTTPS for web traffic; denies everything else |
| Private NACL | Denies SSH and HTTP from all sources except VPC CIDR and bastion subnet |
| Bastion Security Group | SSH ingress from single admin CIDR only |
| Private Security Group | SSH ingress from bastion SG ID only (Security Group referencing) |

### Observability

| Resource | Detail |
|---|---|
| VPC Flow Logs (accepted) | All accepted traffic → CloudWatch log group |
| VPC Flow Logs (rejected) | All rejected traffic → separate log group for security analysis |
| CloudWatch metric filters | SSH brute-force (>10 rejected SSH in 5 min), port scan (>50 unique ports in 1 min) |
| CloudWatch alarms | CPU >80%, EC2 status check failure, SSH brute-force, port scan pattern |
| CloudWatch dashboard | Unified view: NAT bandwidth, EC2 CPU, security event counts |
| SNS topic | Email alerts for all alarms |

### Compute

| Resource | Detail |
|---|---|
| Bastion host | Amazon Linux 2, `t2.micro`, public subnet, hardened SG |
| Private instances (×2) | Amazon Linux 2, `t2.micro`, Apache HTTP server, private subnets |
| IAM instance profiles | SSM + CloudWatch Agent permissions on all instances |

---

## Deployment

### Prerequisites

- Terraform ≥ 1.0
- AWS CLI configured (`aws configure`)
- An existing EC2 Key Pair in the target region

### Steps

```bash
git clone https://github.com/Rolly-M/Cloud-Security-Portfolio.git
cd "Cloud-Security-Portfolio/1 - AWS-Secure-VPC/TF scripts"

terraform init
```

Create `terraform.tfvars`:

```hcl
allowed_ssh_cidr = "1.2.3.4/32"   # your public IP
alert_email      = "you@example.com"
key_name         = "my-keypair"
```

```bash
terraform plan
terraform apply
```

Confirm the SNS email subscription when it arrives.

### Accessing Private Instances

SSH agent forwarding keeps your private key off the bastion:

```bash
ssh-add my-keypair.pem
ssh -A ec2-user@<BASTION_PUBLIC_IP>

# From the bastion:
ssh ec2-user@<PRIVATE_INSTANCE_IP>
```

The bastion's public IP and private instance IPs are Terraform outputs.

### Monitoring Dashboard

```bash
terraform output cloudwatch_dashboard_url
```

Open the URL in the AWS console to view the pre-built dashboard.

---

## Validating the Security Posture

An automated test script checks all the security controls without manual inspection:

```bash
chmod +x test_the_infra.sh
./test_the_infra.sh
```

Tests:
- SSH connectivity to bastion
- SSH jump to private instance via bastion
- Apache web server responding on private instance
- NAT Gateway (outbound internet from private instance)
- CloudWatch alarms deployed
- VPC Flow Logs configured on both log groups

---

## Cleanup

```bash
terraform destroy
```

The NAT Gateway and EC2 instances are the primary cost drivers. `terraform destroy` removes everything managed by this configuration.
