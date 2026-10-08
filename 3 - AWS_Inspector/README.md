# Project 3 — AWS Inspector v2: Vulnerability Scanning

[![AWS Inspector](https://img.shields.io/badge/AWS-Inspector_v2-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/inspector/)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.0-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org/)

Continuous EC2 vulnerability scanning with automated notification and instance tagging. Inspector v2 scans running instances for OS and package CVEs; a Lambda function processes findings, tags affected instances with vulnerability metadata, and fires SNS alerts for HIGH and CRITICAL severity findings.

Builds on the VPC from Project 1. Findings feed into the GuardDuty pipeline from Project 2.

---

## How It Works

```
Inspector v2 (continuous EC2 scan)
        │
        │  new finding
        ▼
EventBridge Rule  ── filters: source=aws.inspector2, severity HIGH|CRITICAL
        │
        ▼
Lambda (finding_processor.py)
        │
        ├── log_finding()          always — structured CloudWatch audit log
        │
        ├── tag_instance()         severity ≥ threshold AND TAG_INSTANCES=true
        │     └── ec2:CreateTags   InspectorSeverity, FindingType,
        │                          VulnerabilityId, LastScanned
        │
        └── send_notification()    severity ≥ threshold
              └── sns:Publish      formatted finding summary → email / Slack
```

Inspector communicates with instances via the SSM Agent — no open ports, no manual agent installs. New findings appear within minutes of a CVE being published.

---

## Project Structure

```
3 - AWS_Inspector/
├── terraform/
│   ├── main.tf          # Provider config, locals
│   ├── inspector.tf     # Inspector enabler, SNS topic + policy + email subscription
│   ├── ec2.tf           # t3.micro test instances, IAM instance profile, SSM association
│   ├── iam.tf           # Lambda execution role (EC2, SNS, Inspector2, CloudWatch Logs)
│   ├── eventbridge.tf   # Rule routing Inspector2 findings → Lambda
│   ├── lambda.tf        # Function, env vars, 14-day log group
│   ├── variables.tf
│   ├── outputs.tf
│   └── data.tf
├── lambda/
│   ├── finding_processor.py   # Lambda handler — 8 functions, fully unit-tested
│   └── requirements.txt
└── README.md
```

---

## Infrastructure

| Resource | Detail |
|---|---|
| `aws_inspector2_enabler` | EC2 scanning only — Lambda/ECR scanning costs extra and can be enabled separately |
| EC2 test instances (×2) | `t3.micro`, Amazon Linux 2, no public IP, IMDSv2 enforced, SSM-accessible |
| IAM instance profile | SSM + Inspector read permissions; no SSH key needed |
| EventBridge rule | Matches `aws.inspector2` source, detail-type `Inspector2 Finding` |
| Lambda function | Python 3.11, 256 MB, 60 s timeout |
| SNS topic | KMS-encrypted (AWS-managed key); email subscription |
| CloudWatch Log Group | 14-day retention |

---

## Deployment

### Prerequisites
- Terraform ≥ 1.0
- AWS CLI configured

```bash
cd "3 - AWS_Inspector/terraform"
terraform init
terraform plan -var="alert_email=you@example.com"
terraform apply -var="alert_email=you@example.com"
```

Confirm the SNS email subscription when it arrives. To deploy into the Project 1 VPC, set `vpc_id` and `subnet_ids` in `terraform.tfvars`.

### Lambda Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SEVERITY_THRESHOLD` | `7.0` | Minimum score to trigger tagging and notification |
| `TAG_INSTANCES` | `true` | Tag affected EC2 instances with finding metadata |
| `SNS_TOPIC_ARN` | — | Alert topic (set automatically by Terraform) |

---

## Verifying Findings

Inspector generates real findings within minutes of deployment if the test instances have unpatched packages.

```bash
# List active findings
aws inspector2 list-findings \
  --filter-criteria '{"findingStatus":[{"comparison":"EQUALS","value":"ACTIVE"}]}' \
  --query 'findings[].{Title:title,Severity:severity,Instance:resources[0].id}'

# Watch Lambda process findings in real time
aws logs tail /aws/lambda/inspector-security-dev-finding-processor --follow

# Confirm instance tags applied by Lambda
aws ec2 describe-tags \
  --filters "Name=key,Values=InspectorSeverity" \
  --query 'Tags[].{Instance:ResourceId,Severity:Value}'
```

---

## Tests

```bash
python -m pytest tests/test_inspector_finding_processor.py -v
```

Covers: severity label mapping for all 5 bands, CVSS max extraction across multiple scores, instance tagging success and ClientError paths, SNS notification gating, threshold boundary (6.9 vs 7.0), and the full Lambda handler.

---

## Cost

| Resource | Cost |
|---|---|
| Inspector v2 EC2 scanning | ~$0.11 / instance / month |
| Lambda | Free tier (1M requests/month) |
| EventBridge | Free (first 1M events/month) |
| SNS | Free (first 1M notifications/month) |
| CloudWatch Logs | ~$0.50/GB ingested |

Run `terraform destroy` when done to stop Inspector scanning charges.
