# Cloud Security Portfolio — Rolly Mougoue

[![AWS Solutions Architect – Associate](https://img.shields.io/badge/AWS-Solutions_Architect_Associate-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)](https://www.credly.com/badges/33105d15-a047-4119-a4e0-1a145bae0381/public_url)
[![ISC2 CC](https://img.shields.io/badge/ISC2-Certified_in_Cybersecurity-005A8B?style=flat-square&logo=isc2&logoColor=white)](https://www.isc2.org/certifications/cc)
[![CompTIA CySA+](https://img.shields.io/badge/CompTIA-CySA%2B-E3002B?style=flat-square&logo=comptia&logoColor=white)](https://www.credly.com/badges/a986ca8c-0a1b-4d0d-b2f6-9071278d1447/public_url)
[![Tests](https://img.shields.io/badge/tests-73_passing-brightgreen?style=flat-square&logo=pytest&logoColor=white)](#)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Rolly_Mougoue-0A66C2?style=flat-square&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/rollymougoue/)

Cloud Security Engineer focused on AWS-native security automation. This portfolio contains production-quality infrastructure and Lambda code — built with Terraform, tested with pytest and moto, and designed to reflect real security engineering work rather than tutorial exercises.

---

## Projects

### [1 — AWS Secure VPC](./1%20-%20AWS-Secure-VPC/TF%20scripts/)
A hardened multi-AZ VPC built entirely in Terraform. Implements defense-in-depth with layered Network ACLs, Security Group referencing, VPC Flow Logs split into accepted/rejected streams, and a CloudWatch dashboard with security-focused alarms (SSH brute-force detection, port scan heuristics, CPU anomalies). Access to private instances is gated through a bastion host using SSH agent forwarding — no direct internet exposure.

**Key techniques:** multi-AZ subnet segmentation, NACL deny rules, Security Group chaining, VPC Flow Log forensics, CloudWatch metric filters for security events, SNS alerting.

---

### [2 — GuardDuty Threat Detection & Auto-Remediation](./2%20-%20AWS_Guard_Duty/)
An event-driven security response pipeline that takes a GuardDuty finding from detection to automated containment without human intervention. EventBridge routes findings to a Lambda function that isolates compromised EC2 instances (security group replacement), disables IAM credentials (key deactivation + deny-all inline policy), creates forensic EBS snapshots before containment, and fires notifications to SNS and Slack.

Includes a threat simulation toolkit — a Python test harness and a DNS exfiltration simulator — to generate findings that exercise the remediation pipeline end-to-end.

The Lambda remediation logic has full unit-test coverage using pytest and moto (AWS service mocking), with 73 tests covering all remediation paths, error cases, severity thresholds, and feature flags.

**Key techniques:** GuardDuty detector configuration, EventBridge rules, Lambda IAM least-privilege, EC2 quarantine via security group replacement, IAM credential revocation, KMS-encrypted S3 findings storage, forensic EBS snapshots, moto-based unit testing.

---

## Tech Stack

| Layer | Tools |
|---|---|
| Infrastructure | Terraform ≥ 1.0, AWS Provider ~5.0 |
| Compute | AWS Lambda (Python 3.11), EC2 |
| Security services | GuardDuty, EventBridge, IAM, KMS, VPC Flow Logs |
| Alerting | SNS, Slack Webhooks |
| Testing | pytest, moto, unittest.mock |
| CI | GitHub Actions |

---

## Running the Tests

```bash
pip install -r requirements-dev.txt
python -m pytest tests/ -q
```

73 tests, no AWS credentials required — all AWS calls are intercepted by moto.

---

## Contact

- Email: rollymk25@gmail.com
- LinkedIn: [linkedin.com/in/rollymougoue](https://www.linkedin.com/in/rollymougoue/)
- Open to Cloud Security Engineer roles (AWS focus, EU/Remote)
