# Cloud Security Portfolio — Rolly Mougoue

[![AWS Solutions Architect – Associate](https://img.shields.io/badge/AWS-Solutions_Architect_Associate-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)](https://www.credly.com/badges/33105d15-a047-4119-a4e0-1a145bae0381/public_url)
[![ISC2 CC](https://img.shields.io/badge/ISC2-Certified_in_Cybersecurity-005A8B?style=flat-square&logo=isc2&logoColor=white)](https://www.isc2.org/certifications/cc)
[![CompTIA CySA+](https://img.shields.io/badge/CompTIA-CySA%2B-E3002B?style=flat-square&logo=comptia&logoColor=white)](https://www.credly.com/badges/a986ca8c-0a1b-4d0d-b2f6-9071278d1447/public_url)
[![Tests](https://img.shields.io/badge/tests-154_passing-brightgreen?style=flat-square&logo=pytest&logoColor=white)](#)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Rolly_Mougoue-0A66C2?style=flat-square&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/rollymougoue/)

Cloud Security Engineer focused on AWS-native security automation. This portfolio contains production-quality infrastructure and Lambda code — built with Terraform, tested with pytest and moto, and designed to reflect real security engineering work rather than tutorial exercises.

---

## Projects

### [1 — AWS Secure VPC](./1%20-%20AWS-Secure-VPC/TF%20scripts/)
A hardened multi-AZ VPC built entirely in Terraform. Implements defense-in-depth with layered Network ACLs, Security Group referencing, VPC Flow Logs split into accepted/rejected streams, and a CloudWatch dashboard with security-focused alarms (SSH brute-force detection, port scan heuristics, CPU anomalies). Access to private instances is gated through a bastion host using SSH agent forwarding — no direct internet exposure.

**Key techniques:** multi-AZ subnet segmentation, NACL deny rules, Security Group chaining, VPC Flow Log forensics, CloudWatch metric filters, SNS alerting.

---

### [2 — GuardDuty Threat Detection & Auto-Remediation](./2%20-%20AWS_Guard_Duty/)
An event-driven security response pipeline that takes a GuardDuty finding from detection to automated containment without human intervention. EventBridge routes findings to a Lambda function that isolates compromised EC2 instances (security group replacement), disables IAM credentials (key deactivation + deny-all inline policy), creates forensic EBS snapshots, and fires SNS and Slack notifications. Includes a Python threat simulation toolkit to generate findings end-to-end.

**Key techniques:** GuardDuty detector, EventBridge rules, EC2 quarantine via SG replacement, IAM credential revocation, KMS-encrypted S3 findings storage, forensic snapshots, moto-based unit testing.

---

### [3 — AWS Inspector v2: Vulnerability Scanning](./3%20-%20AWS_Inspector/)
Continuous CVE scanning for EC2 instances. Inspector communicates via the SSM Agent (no open ports); findings route through EventBridge to a Lambda that tags affected instances with vulnerability metadata and fires SNS alerts. Covers the full severity band from INFORMATIONAL to CRITICAL.

**Key techniques:** Inspector v2 EC2 scanning, SSM Agent integration, EventBridge pattern filtering, EC2 tag-based vulnerability tracking.

---

### [4 — AWS WAF: Web Application Firewall](./4%20-%20AWS_WAF/)
WAFv2 protecting an API Gateway HTTP API with five layered rules: OWASP Common Rule Set, SQL injection, known bad inputs (Log4Shell, SSRF, path traversal), per-IP rate limiting, and a custom IP blocklist. Logs to CloudWatch. Uses API Gateway instead of an ALB to save ~$18/month.

**Key techniques:** WAFv2 managed rule groups, rate-based rules, CloudWatch WAF logging, API Gateway HTTP API, rule logic unit tests (33 pytest cases).

---

### [5 — AWS Macie + KMS: PII Classification](./5%20-%20AWS_Macie_KMS/)
Automated PII discovery and quarantine for S3 data. Weekly Macie classification jobs scan a sensitive-data bucket using built-in detectors and custom identifiers (AWS account numbers, employee IDs). Findings trigger a Lambda that copies flagged objects to an isolated quarantine bucket, deletes the originals, tags them with classification metadata, and fires SNS alerts. All buckets encrypted with a single rotating KMS CMK.

**Key techniques:** Macie v2 scheduled classification jobs, custom data identifiers, KMS CMK with key rotation, S3 object quarantine via copy+delete, EventBridge-driven response.

---

## Tech Stack

| Layer | Tools |
|---|---|
| Infrastructure | Terraform ≥ 1.0, AWS Provider ~5.0 |
| Compute | AWS Lambda (Python 3.11), EC2 |
| Security services | GuardDuty, Inspector v2, WAFv2, Macie v2, EventBridge, IAM, KMS, VPC Flow Logs |
| Alerting | SNS, Slack Webhooks |
| Testing | pytest, moto, unittest.mock |
| CI | GitHub Actions (Python 3.11 + 3.12) |

---

## Running the Tests

```bash
pip install -r requirements-dev.txt
python -m pytest tests/ -q
```

154 tests, no AWS credentials required — all AWS calls are intercepted by moto.

---

## Contact

- Email: rollymk25@gmail.com
- LinkedIn: [linkedin.com/in/rollymougoue](https://www.linkedin.com/in/rollymougoue/)
- Open to Cloud Security Engineer roles (AWS focus, EU/Remote)
