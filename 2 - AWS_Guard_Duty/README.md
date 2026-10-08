# Project 2 — GuardDuty Threat Detection & Auto-Remediation

[![AWS GuardDuty](https://img.shields.io/badge/AWS-GuardDuty-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/guardduty/)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.0-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org/)
[![Tests](https://img.shields.io/badge/tests-73_passing-brightgreen?style=flat-square&logo=pytest&logoColor=white)](#running-tests)

An end-to-end AWS security response pipeline: GuardDuty detects a threat, EventBridge routes the finding to Lambda, and Lambda executes containment — all without human intervention. The entire remediation function is unit-tested with moto so the logic can be validated in CI without touching a real AWS account.

---

## What It Does

```
GuardDuty Finding
      │
      ▼
EventBridge Rule  ──────────────────────────────────────────────────────┐
      │                                                                  │
      ▼                                                                  │
Lambda (remediation_handler.py)                                         │
      │                                                                  │
      ├─── EC2 finding? ──► Create forensic EBS snapshot                │
      │                     Replace security groups with quarantine SG  │
      │                                                                  │
      ├─── IAM finding? ──► Disable access key                          │
      │                     Attach deny-all inline policy               │
      │                                                                  │
      ├─── S3 finding?  ──► Log for review                              │
      │                                                                  │
      ├─── Malicious IP? ─► Log for WAF integration                     │
      │                                                                  │
      └─── Always ───────► SNS + Slack notification                     │
                            Store finding JSON in S3 (KMS-encrypted)   ◄┘
```

### Remediation Details

**EC2 Compromise** (e.g. `UnauthorizedAccess:EC2/SSHBruteForce`, `CryptoCurrency:EC2/BitcoinTool`)
- Snapshots all EBS volumes before touching the instance, tagging each with the finding ID and severity for the forensics team
- Replaces all security groups with a quarantine SG (zero ingress/egress), tagging the instance with its original SGs so recovery is reversible
- Controlled by `SNAPSHOT_INSTANCE` and `ISOLATE_EC2` feature flags

**IAM Credential Theft** (e.g. `UnauthorizedAccess:IAMUser/ConsoleLoginSuccess.B`)
- Calls `update_access_key(Status=Inactive)` on the compromised key
- Attaches a deny-all inline policy (`GuardDuty-Quarantine-DenyAll`) to prevent any further actions regardless of other policies
- Controlled by `DISABLE_IAM_CREDENTIALS` feature flag

**Severity Gating**
All remediation is gated by `SEVERITY_THRESHOLD` (default 7.0). Findings below the threshold receive a notification but no automated action. `ENABLE_AUTO_REMEDIATION=false` disables all automated actions globally while keeping notifications on.

---

## Project Structure

```
2 - AWS_Guard_Duty/
├── terraform/
│   ├── main.tf              # Provider config, KMS key, random suffix
│   ├── guardduty.tf         # Detector, S3 findings export, trusted/malicious IP sets
│   ├── eventbridge.tf       # Rule routing findings to Lambda
│   ├── lambda.tf            # Function, environment variables, log group
│   ├── iam.tf               # Least-privilege execution role
│   ├── sns.tf               # Alert topic + email subscription
│   ├── variables.tf
│   ├── outputs.tf
│   └── data.tf
├── lambda/
│   ├── remediation_handler.py   # Lambda function (14 functions, fully tested)
│   └── requirements.txt
├── threat-simulation/
│   ├── guardduty_tester.py      # GuardDuty finding generator + remediation verifier
│   ├── dns_exfiltration.py      # DNS-based exfiltration simulator
│   └── simulate_threats.sh      # Shell wrapper for common test scenarios
└── README.md
```

---

## Infrastructure

Deployed via Terraform. Key resources:

| Resource | Purpose |
|---|---|
| `aws_guardduty_detector` | Enables GuardDuty with S3, Kubernetes, and malware protection |
| `aws_s3_bucket` (findings) | KMS-encrypted storage for finding exports; lifecycle transitions to Glacier at 90 days |
| `aws_guardduty_ipset` | Trusted IP allowlist (RFC1918 ranges) |
| `aws_guardduty_threatintelset` | Malicious IP feed for testing |
| `aws_cloudwatch_event_rule` | Routes HIGH severity findings to Lambda |
| `aws_lambda_function` | Python 3.11 remediation handler |
| `aws_sns_topic` | Email + Slack alerting |
| `aws_kms_key` | Encrypts findings bucket, SNS topic, and CloudWatch logs |

---

## Deployment

### Prerequisites
- Terraform ≥ 1.0
- AWS CLI configured (`aws configure`)
- An SNS-subscribed email address for alerts

### Steps

```bash
git clone https://github.com/Rolly-M/Cloud-Security-Portfolio.git
cd "Cloud-Security-Portfolio/2 - AWS_Guard_Duty/terraform"

terraform init
terraform plan -var="alert_email=you@example.com"
terraform apply -var="alert_email=you@example.com"
```

Confirm the SNS email subscription when prompted. Outputs include the Lambda function name and findings bucket ARN.

To deploy in the same VPC as Project 1, set `vpc_id` in `terraform.tfvars`.

### Environment Variables (Lambda)

| Variable | Default | Description |
|---|---|---|
| `SEVERITY_THRESHOLD` | `7.0` | Minimum severity to trigger remediation |
| `ENABLE_AUTO_REMEDIATION` | `true` | Master kill-switch for automated actions |
| `ISOLATE_EC2` | `true` | Replace instance security groups with quarantine SG |
| `SNAPSHOT_INSTANCE` | `true` | Create forensic EBS snapshots |
| `DISABLE_IAM_CREDENTIALS` | `true` | Disable keys + attach deny policy |
| `QUARANTINE_SG_ID` | — | Security group ID with no ingress/egress |
| `FINDINGS_BUCKET` | — | S3 bucket for finding JSON storage |
| `SNS_TOPIC_ARN` | — | SNS topic for email alerts |
| `SLACK_WEBHOOK_URL` | — | Slack incoming webhook URL |

---

## Running Tests

No AWS credentials needed — all calls are intercepted by [moto](https://github.com/getmoto/moto).

```bash
pip install -r requirements-dev.txt
python -m pytest tests/ -q
```

```
73 passed in 18s
```

Test coverage includes:
- All 5 remediation paths (EC2, IAM, S3, IP blocking, routing logic)
- Severity threshold boundary (6.9 vs 7.0 vs 8.0)
- Feature flag independence (`ISOLATE_EC2=false` does not suppress snapshots)
- `ENABLE_AUTO_REMEDIATION=false` skips remediation but sends notification
- ClientError handling for every AWS call (failure in one path doesn't crash the handler)
- SNS/Slack notification failure isolation (notification error does not convert a 200 to 500)
- S3 KMS storage — correct key path format and encryption header
- IAM deny-all policy attachment (with and without an access key ID present)
- DNS exfiltration chunking, subdomain format, and socket error handling

---

## Threat Simulation

After deployment, generate findings to exercise the pipeline:

```bash
cd threat-simulation

# Generate a specific finding category
python3 guardduty_tester.py --action generate --category ec2_crypto

# Run a full end-to-end test (generate → wait → verify remediation → report)
python3 guardduty_tester.py --action test --category iam_credential

# Simulate DNS-based data exfiltration (triggers GuardDuty DNS findings)
python3 dns_exfiltration.py --mode exfil --verbose
```

Available finding categories: `ec2_crypto`, `ec2_backdoor`, `ec2_trojan`, `iam_credential`, `iam_persistence`, `s3_exfiltration`, `s3_policy`, `recon`.

> **Note:** The `--action test` and `--mode trigger` commands generate real GuardDuty findings. Only run them in a dedicated test account.

---

## Verify Remediation

```bash
# Watch Lambda logs in real time
aws logs tail /aws/lambda/guardduty-security-dev-remediation-handler --follow

# Confirm EC2 quarantine (security group should be quarantine-only)
aws ec2 describe-instances --instance-ids <instance-id> \
  --query 'Reservations[].Instances[].{ID:InstanceId,SGs:SecurityGroups,Tags:Tags}'

# Check stored findings in S3
aws s3 ls s3://<findings-bucket>/findings/ --recursive
```

---

## Cleanup

```bash
cd terraform
terraform destroy
```

Note: KMS keys are scheduled for deletion (7-day minimum waiting period) rather than deleted immediately. Forensic snapshots are not removed by Terraform — review them before deletion if any real security incidents occurred during testing.
