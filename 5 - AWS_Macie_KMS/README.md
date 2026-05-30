# Project 5 — AWS Macie + KMS: PII Classification & Data Protection

[![AWS Macie](https://img.shields.io/badge/AWS-Macie-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/macie/)
[![AWS KMS](https://img.shields.io/badge/AWS-KMS-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/kms/)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.0-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org/)

Automated PII discovery and response for S3 data. Macie runs weekly classification jobs against a sensitive-data bucket; when findings are published, a Lambda function quarantines the affected objects (copy to an isolated bucket, delete the original), tags them with classification metadata, and fires SNS alerts.

All S3 buckets are encrypted with a single customer-managed KMS key with automatic rotation.

---

## How It Works

```
S3 (sensitive-data bucket)
        │
        │  weekly Macie classification job
        ▼
Macie v2  ── custom identifiers: AWS account numbers, employee IDs
        │
        │  finding published (FIFTEEN_MINUTES frequency)
        ▼
EventBridge Rule  ── source=aws.macie2, detail-type=Macie Finding
        │
        ▼
Lambda (finding_processor.py)
        │
        ├── log_finding()            always — structured audit log
        │
        ├── quarantine_object()      severity ≥ threshold AND ENABLE_QUARANTINE=true
        │     ├── s3:CopyObject  →   quarantine bucket (preserves original key path)
        │     └── s3:DeleteObject    removes from sensitive bucket
        │
        ├── tag_sensitive_object()   severity ≥ threshold
        │     └── s3:PutObjectTagging  MacieFinding, MacieSeverity, FindingType
        │
        └── send_notification()      severity ≥ threshold
              └── sns:Publish        PII types, affected object, actions taken
```

---

## Project Structure

```
5 - AWS_Macie_KMS/
├── terraform/
│   ├── main.tf          # Provider config, random suffix, locals
│   ├── kms.tf           # Single CMK (rotation enabled) shared across all buckets
│   ├── s3.tf            # sensitive, quarantine, clean, and macie-findings buckets
│   ├── macie.tf         # Macie account enablement, weekly job, custom identifiers
│   ├── eventbridge.tf   # Rule routing Macie findings → Lambda
│   ├── lambda.tf        # Function, env vars, log group
│   ├── iam.tf           # Lambda execution role (S3, SNS, KMS, Macie2, CloudWatch Logs)
│   ├── variables.tf
│   ├── outputs.tf
│   └── data.tf
├── lambda/
│   ├── finding_processor.py   # Lambda handler — 8 functions, fully unit-tested
│   └── requirements.txt
├── sample-data/
│   ├── pii_sample.csv         # Fake employee PII (SSN, credit card, AWS account #)
│   ├── pii_sample.json        # Fake PII in JSON format
│   └── clean_data.csv         # Product catalog — no PII (control sample)
└── README.md
```

---

## Infrastructure

### KMS
A single customer-managed key with automatic annual rotation encrypts all four S3 buckets. Using one key instead of one-per-bucket costs $1/month instead of $4/month with no meaningful security reduction for this use case.

### S3 Buckets

| Bucket | Purpose |
|---|---|
| `sensitive-data` | Input bucket scanned by Macie; receives uploaded PII test data |
| `quarantine` | Isolated bucket for objects flagged by Macie; lifecycle transitions to Glacier at 90 days |
| `clean-data` | Verified clean data; objects moved here after manual review |
| `macie-findings` | Macie findings export destination |

All buckets: versioning enabled, KMS-encrypted (bucket key enabled), all public access blocked.

### Macie

| Setting | Value | Reason |
|---|---|---|
| Job type | SCHEDULED (weekly) | Continuous monitoring costs ~10× more at scale |
| Sampling | 100% | All objects in scope are scanned |
| File types | csv, json, txt, log, xml | Targeted scope avoids scanning binaries |
| Custom identifiers | AWS account numbers (`\b\d{12}\b`), employee IDs (`EMP-\d{6}`) | Catches internal data patterns Macie's built-ins miss |

---

## Deployment

### Prerequisites
- Terraform ≥ 1.0
- AWS CLI configured
- Macie not already enabled in the account (Terraform manages it)

```bash
cd "5 - AWS_Macie_KMS/terraform"
terraform init
terraform plan -var="alert_email=you@example.com"
terraform apply -var="alert_email=you@example.com"
```

### Upload Test Data

```bash
SENSITIVE_BUCKET=$(terraform output -raw sensitive_bucket_name)

aws s3 cp ../sample-data/pii_sample.csv  s3://${SENSITIVE_BUCKET}/data/pii_sample.csv
aws s3 cp ../sample-data/pii_sample.json s3://${SENSITIVE_BUCKET}/data/pii_sample.json
aws s3 cp ../sample-data/clean_data.csv  s3://${SENSITIVE_BUCKET}/data/clean_data.csv
```

The next scheduled Macie job will scan these objects and generate findings for the PII samples.

### Lambda Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SEVERITY_THRESHOLD` | `7.0` | Minimum score to trigger quarantine and notification |
| `ENABLE_QUARANTINE` | `true` | Copy flagged objects to quarantine bucket and delete originals |
| `QUARANTINE_BUCKET` | — | Set automatically by Terraform |
| `SENSITIVE_BUCKET` | — | Set automatically by Terraform |
| `SNS_TOPIC_ARN` | — | Set automatically by Terraform |

---

## Verifying the Pipeline

```bash
# List Macie findings
aws macie2 list-findings \
  --finding-criteria '{"criterion":{"severity.score":{"gte":1}}}' \
  --query 'findingIds'

# Get finding details
aws macie2 get-findings --finding-ids <finding-id>

# Watch Lambda process a finding
aws logs tail /aws/lambda/macie-kms-security-dev-finding-processor --follow

# Check quarantine bucket
QUARANTINE=$(terraform output -raw quarantine_bucket_name)
aws s3 ls s3://${QUARANTINE}/ --recursive

# Verify object tags were applied
aws s3api get-object-tagging \
  --bucket ${QUARANTINE} \
  --key data/pii_sample.csv
```

---

## Tests

```bash
python -m pytest tests/test_macie_finding_processor.py -v
```

Covers: `parse_finding` with dict and string `type` fields, missing `resourcesAffected`, empty PII types; `quarantine_object` copies to quarantine and deletes original (verified via S3 list), preserves key path, handles ClientError; `tag_sensitive_object` applies correct tags; `process_finding` threshold gating, `ENABLE_QUARANTINE=false`, no bucket/key; `send_notification` gating; full `lambda_handler` flow.

---

## Cost

| Resource | Cost |
|---|---|
| KMS CMK | $1.00 / month |
| Macie (first 1 GB/month) | Free |
| Macie beyond free tier | $1.00 / GB scanned |
| S3 (4 buckets, minimal data) | < $0.01 / month |
| Lambda + EventBridge | Free tier |
| **Total (demo)** | **~$1 / month** |

The weekly scheduled job and small sample files keep Macie well within the free tier. Run `terraform destroy` to disable Macie and remove all resources when done.

> **Note:** KMS keys cannot be deleted immediately — they are scheduled for deletion with a 7-day minimum waiting period.
