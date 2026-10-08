###############################################################################
# Macie — Sensitive data discovery
# Using SCHEDULED jobs (not continuous) to minimize cost
###############################################################################

# Enable Macie for the account
resource "aws_macie2_account" "main" {
  status                       = "ENABLED"
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

# ---------------------------------------------------------------------------
# Custom Data Identifiers — additional PII patterns beyond Macie's built-ins
# ---------------------------------------------------------------------------

resource "aws_macie2_custom_data_identifier" "aws_account_numbers" {
  name        = "AWS-Account-Numbers"
  regex       = "\\b\\d{12}\\b"
  description = "12-digit AWS account numbers"

  depends_on = [aws_macie2_account.main]
}

resource "aws_macie2_custom_data_identifier" "employee_ids" {
  name        = "Internal-Employee-IDs"
  regex       = "EMP-\\d{6}"
  description = "Internal employee IDs"

  depends_on = [aws_macie2_account.main]
}

# ---------------------------------------------------------------------------
# Scheduled Classification Job — WEEKLY scan of the sensitive bucket
# Scheduled jobs cost far less than continuous monitoring
# ---------------------------------------------------------------------------

resource "aws_macie2_classification_job" "sensitive_data_scan" {
  name        = "${local.name_prefix}-weekly-scan"
  description = "Weekly scheduled scan of sensitive data bucket for PII and custom identifiers"
  job_type    = "SCHEDULED"

  schedule_frequency {
    weekly_schedule = var.scan_schedule == "WEEKLY" ? "MONDAY" : null
  }

  sampling_percentage = 100

  s3_job_definition {
    bucket_definitions {
      account_id = data.aws_caller_identity.current.account_id
      buckets    = [aws_s3_bucket.sensitive.id]
    }

    scoping {
      includes {
        and {
          simple_scope_term {
            comparator = "EQ"
            key        = "OBJECT_EXTENSION"
            values     = ["csv", "json", "txt", "log", "xml"]
          }
        }
      }
    }
  }

  custom_data_identifier_ids = [
    aws_macie2_custom_data_identifier.aws_account_numbers.id,
    aws_macie2_custom_data_identifier.employee_ids.id
  ]

  depends_on = [aws_macie2_account.main]

  tags = {
    Name = "${local.name_prefix}-weekly-scan"
  }
}

# ---------------------------------------------------------------------------
# Findings Filter — capture HIGH and CRITICAL severity findings
# ---------------------------------------------------------------------------

resource "aws_macie2_findings_filter" "high_severity" {
  name        = "${local.name_prefix}-high-severity-filter"
  description = "Filter for HIGH and CRITICAL severity Macie findings"
  action      = "ARCHIVE"

  finding_criteria {
    criterion {
      field  = "severity.score"
      gte    = 7
    }
  }

  depends_on = [aws_macie2_account.main]
}
