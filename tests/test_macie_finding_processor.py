"""
Unit tests for 5 - AWS_Macie_KMS/lambda/finding_processor.py

All AWS calls intercepted by moto. Uses importlib to load the module by
explicit path, avoiding a name collision with the Inspector finding_processor.
"""

import importlib.util
import json
import os
import boto3
import pytest
from moto import mock_aws
from unittest.mock import patch
from botocore.exceptions import ClientError

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
_LAMBDA_PATH = os.path.join(REPO_ROOT, "5 - AWS_Macie_KMS", "lambda", "finding_processor.py")


# ---------------------------------------------------------------------------
# Loader
# ---------------------------------------------------------------------------

def _load(monkeypatch, **overrides):
    defaults = {
        "ENVIRONMENT": "test",
        "SNS_TOPIC_ARN": "",
        "QUARANTINE_BUCKET": "",
        "SENSITIVE_BUCKET": "test-sensitive",
        "ENABLE_QUARANTINE": "true",
        "SEVERITY_THRESHOLD": "7.0",
        "AWS_DEFAULT_REGION": "us-east-1",
        "AWS_ACCESS_KEY_ID": "testing",
        "AWS_SECRET_ACCESS_KEY": "testing",
        "AWS_SECURITY_TOKEN": "testing",
        "AWS_SESSION_TOKEN": "testing",
    }
    for k, v in {**defaults, **overrides}.items():
        monkeypatch.setenv(k, v)

    spec = importlib.util.spec_from_file_location("macie_fp", _LAMBDA_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    mod.s3_client = boto3.client("s3", region_name="us-east-1")
    mod.sns_client = boto3.client("sns", region_name="us-east-1")
    mod.macie2_client = boto3.client("macie2", region_name="us-east-1")
    return mod


def _macie_event(severity_score=8.0, bucket="my-sensitive-bucket", key="data/employees.csv"):
    return {
        "version": "0",
        "source": "aws.macie2",
        "account": "123456789012",
        "region": "us-east-1",
        "detail-type": "Macie Finding",
        "detail": {
            "id": "macie-finding-001",
            "type": {"id": "SensitiveData:S3Object/Personal"},
            "severity": {"score": severity_score, "description": "HIGH"},
            "title": "S3 object contains personal information",
            "description": "The object contains SSN and credit card data.",
            "accountId": "123456789012",
            "resourcesAffected": {
                "s3Bucket": {"name": bucket},
                "s3Object": {"key": key},
            },
            "classificationDetails": {
                "result": {
                    "sensitiveData": [
                        {"type": "NAME", "count": 10},
                        {"type": "NATIONAL_IDENTIFICATION_NUMBER", "count": 3},
                    ]
                }
            },
        },
    }


# ---------------------------------------------------------------------------
# parse_finding
# ---------------------------------------------------------------------------

class TestParseFinding:
    def test_well_formed_event_extracts_all_fields(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(_macie_event())
        assert result["finding_id"] == "macie-finding-001"
        assert result["finding_type"] == "SensitiveData:S3Object/Personal"
        assert result["severity_score"] == 8.0
        assert result["affected_bucket"] == "my-sensitive-bucket"
        assert result["affected_object"] == "data/employees.csv"
        assert len(result["pii_types"]) == 2

    def test_finding_type_as_string_used_directly(self, monkeypatch):
        event = _macie_event()
        event["detail"]["type"] = "SensitiveData:S3Object/Financial"
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(event)
        assert result["finding_type"] == "SensitiveData:S3Object/Financial"

    def test_missing_resources_affected_gives_none_bucket_and_key(self, monkeypatch):
        event = _macie_event()
        del event["detail"]["resourcesAffected"]
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(event)
        assert result["affected_bucket"] is None
        assert result["affected_object"] is None

    def test_severity_score_coerced_to_float(self, monkeypatch):
        event = _macie_event()
        event["detail"]["severity"]["score"] = "9"
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(event)
        assert isinstance(result["severity_score"], float)

    def test_none_event_returns_none(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(None)
        assert result is None

    def test_empty_pii_types_when_no_classification(self, monkeypatch):
        event = _macie_event()
        del event["detail"]["classificationDetails"]
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(event)
        assert result["pii_types"] == []


# ---------------------------------------------------------------------------
# quarantine_object
# ---------------------------------------------------------------------------

class TestQuarantineObject:
    def _finding(self):
        return {
            "finding_id": "f1",
            "finding_type": "SensitiveData:S3Object/Personal",
            "severity_score": 8.0,
        }

    def test_successful_quarantine_copies_and_deletes(self, monkeypatch):
        with mock_aws():
            s3 = boto3.client("s3", region_name="us-east-1")
            s3.create_bucket(Bucket="source-bucket")
            s3.create_bucket(Bucket="quarantine-bucket")
            s3.put_object(Bucket="source-bucket", Key="data/file.csv", Body=b"sensitive data")

            m = _load(monkeypatch, QUARANTINE_BUCKET="quarantine-bucket")
            m.s3_client = s3
            result = m.quarantine_object("source-bucket", "data/file.csv", self._finding())

            # Verify inside mock_aws context
            objects = s3.list_objects_v2(Bucket="source-bucket")
            quarantine_objects = s3.list_objects_v2(Bucket="quarantine-bucket")

        assert result["status"] == "SUCCESS"
        assert result["action"] == "QUARANTINE_OBJECT"
        assert result["quarantine_bucket"] == "quarantine-bucket"
        assert objects.get("KeyCount", 0) == 0          # original deleted
        assert quarantine_objects["KeyCount"] == 1       # copy exists

    def test_client_error_returns_failed_dict(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, QUARANTINE_BUCKET="nonexistent-quarantine")
            result = m.quarantine_object("nonexistent-source", "key.csv", self._finding())
        assert result["status"] == "FAILED"
        assert result["action"] == "QUARANTINE_OBJECT"
        assert "error" in result

    def test_quarantine_key_preserves_original_path(self, monkeypatch):
        with mock_aws():
            s3 = boto3.client("s3", region_name="us-east-1")
            s3.create_bucket(Bucket="src")
            s3.create_bucket(Bucket="qbucket")
            s3.put_object(Bucket="src", Key="nested/path/file.csv", Body=b"data")

            m = _load(monkeypatch, QUARANTINE_BUCKET="qbucket")
            m.s3_client = s3
            result = m.quarantine_object("src", "nested/path/file.csv", self._finding())

        assert result["quarantine_key"] == "nested/path/file.csv"


# ---------------------------------------------------------------------------
# tag_sensitive_object
# ---------------------------------------------------------------------------

class TestTagSensitiveObject:
    def _finding(self):
        return {
            "finding_id": "f1",
            "finding_type": "SensitiveData:S3Object/Personal",
            "severity_score": 8.0,
        }

    def test_successful_tag_returns_success(self, monkeypatch):
        with mock_aws():
            s3 = boto3.client("s3", region_name="us-east-1")
            s3.create_bucket(Bucket="data-bucket")
            s3.put_object(Bucket="data-bucket", Key="file.csv", Body=b"data")

            m = _load(monkeypatch)
            m.s3_client = s3
            result = m.tag_sensitive_object("data-bucket", "file.csv", self._finding())

            # Verify tags inside mock_aws context
            tags = s3.get_object_tagging(Bucket="data-bucket", Key="file.csv")["TagSet"]
            tag_keys = {t["Key"] for t in tags}

        assert result["status"] == "SUCCESS"
        assert result["action"] == "TAG_SENSITIVE_OBJECT"
        assert "MacieFinding" in tag_keys
        assert "MacieSeverity" in tag_keys
        assert "FindingType" in tag_keys

    def test_client_error_returns_failed_dict(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            with patch.object(m.s3_client, "put_object_tagging",
                              side_effect=ClientError({"Error": {"Code": "NoSuchKey", "Message": "x"}}, "PutObjectTagging")):
                result = m.tag_sensitive_object("bucket", "missing.csv", self._finding())
        assert result["status"] == "FAILED"


# ---------------------------------------------------------------------------
# process_finding
# ---------------------------------------------------------------------------

class TestProcessFinding:
    def _finding(self, severity=8.0, bucket="my-bucket", key="data/file.csv"):
        return {
            "finding_id": "f1",
            "finding_type": "SensitiveData:S3Object/Personal",
            "severity_score": severity,
            "title": "PII detected",
            "description": "",
            "account_id": "123456789012",
            "region": "us-east-1",
            "affected_bucket": bucket,
            "affected_object": key,
            "pii_types": [{"type": "NAME"}],
        }

    def test_below_threshold_returns_empty_actions(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, SEVERITY_THRESHOLD="7.0")
            with patch.object(m, "quarantine_object") as mock_q, \
                 patch.object(m, "tag_sensitive_object") as mock_t, \
                 patch.object(m, "send_notification") as mock_n:
                result = m.process_finding(self._finding(severity=6.9))
            mock_q.assert_not_called()
            mock_t.assert_not_called()
            mock_n.assert_not_called()
        assert result == []

    def test_quarantine_disabled_skips_quarantine(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, ENABLE_QUARANTINE="false")
            with patch.object(m, "quarantine_object") as mock_q, \
                 patch.object(m, "tag_sensitive_object", return_value={"action": "TAG_SENSITIVE_OBJECT", "status": "SUCCESS"}), \
                 patch.object(m, "send_notification"):
                m.process_finding(self._finding(severity=8.0))
            mock_q.assert_not_called()

    def test_no_bucket_skips_quarantine_and_tagging(self, monkeypatch):
        finding = self._finding()
        finding["affected_bucket"] = None
        finding["affected_object"] = None
        with mock_aws():
            m = _load(monkeypatch)
            with patch.object(m, "quarantine_object") as mock_q, \
                 patch.object(m, "tag_sensitive_object") as mock_t, \
                 patch.object(m, "send_notification"):
                m.process_finding(finding)
            mock_q.assert_not_called()
            mock_t.assert_not_called()

    def test_above_threshold_quarantine_and_tag_called(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, SEVERITY_THRESHOLD="7.0", ENABLE_QUARANTINE="true")
            quarantine_result = {"action": "QUARANTINE_OBJECT", "status": "SUCCESS"}
            tag_result = {"action": "TAG_SENSITIVE_OBJECT", "status": "SUCCESS"}
            with patch.object(m, "quarantine_object", return_value=quarantine_result), \
                 patch.object(m, "tag_sensitive_object", return_value=tag_result), \
                 patch.object(m, "send_notification"):
                result = m.process_finding(self._finding(severity=8.0))
        assert len(result) == 2
        actions = [a["action"] for a in result]
        assert "QUARANTINE_OBJECT" in actions
        assert "TAG_SENSITIVE_OBJECT" in actions


# ---------------------------------------------------------------------------
# send_notification (Macie)
# ---------------------------------------------------------------------------

class TestSendNotification:
    def _finding(self):
        return {
            "finding_id": "f1",
            "finding_type": "SensitiveData:S3Object/Personal",
            "severity_score": 8.0,
            "title": "PII found",
            "description": "",
            "account_id": "123456789012",
            "region": "us-east-1",
            "affected_bucket": "my-bucket",
            "affected_object": "data/file.csv",
            "pii_types": [],
        }

    def test_no_sns_arn_skips_publish(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, SNS_TOPIC_ARN="")
            with patch.object(m.sns_client, "publish") as mock_pub:
                m.send_notification(self._finding(), [])
            mock_pub.assert_not_called()

    def test_sns_arn_set_calls_publish(self, monkeypatch):
        with mock_aws():
            sns = boto3.client("sns", region_name="us-east-1")
            arn = sns.create_topic(Name="macie-alerts")["TopicArn"]
            m = _load(monkeypatch, SNS_TOPIC_ARN=arn)
            m.sns_client = sns
            m.send_notification(self._finding(), [])  # should not raise

    def test_sns_error_does_not_raise(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:nonexistent")
            m.send_notification(self._finding(), [])  # should not raise


# ---------------------------------------------------------------------------
# lambda_handler (Macie)
# ---------------------------------------------------------------------------

class TestLambdaHandler:
    def test_none_event_returns_400(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            result = m.lambda_handler(None, None)
        assert result["statusCode"] == 400

    def test_valid_high_severity_returns_200(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, SEVERITY_THRESHOLD="7.0")
            with patch.object(m, "process_finding", return_value=[]) as mock_proc:
                result = m.lambda_handler(_macie_event(severity_score=8.0), None)
            mock_proc.assert_called_once()
        assert result["statusCode"] == 200

    def test_body_is_valid_json_with_expected_keys(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            with patch.object(m, "process_finding", return_value=[]):
                result = m.lambda_handler(_macie_event(), None)
        body = json.loads(result["body"])
        assert "message" in body
        assert "actions" in body
        assert "timestamp" in body

    def test_actions_returned_in_response_body(self, monkeypatch):
        actions = [{"action": "QUARANTINE_OBJECT", "status": "SUCCESS"}]
        with mock_aws():
            m = _load(monkeypatch)
            with patch.object(m, "process_finding", return_value=actions):
                result = m.lambda_handler(_macie_event(), None)
        body = json.loads(result["body"])
        assert body["actions"] == actions
