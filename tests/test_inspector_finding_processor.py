"""
Unit tests for 3 - AWS_Inspector/lambda/finding_processor.py

All AWS calls intercepted by moto. Uses importlib to load the module by
explicit path, avoiding a name collision with the Macie finding_processor.
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
_LAMBDA_PATH = os.path.join(REPO_ROOT, "3 - AWS_Inspector", "lambda", "finding_processor.py")


# ---------------------------------------------------------------------------
# Loader
# ---------------------------------------------------------------------------

def _load(monkeypatch, **overrides):
    defaults = {
        "ENVIRONMENT": "test",
        "SNS_TOPIC_ARN": "",
        "SEVERITY_THRESHOLD": "7.0",
        "TAG_INSTANCES": "true",
        "AWS_DEFAULT_REGION": "us-east-1",
        "AWS_ACCESS_KEY_ID": "testing",
        "AWS_SECRET_ACCESS_KEY": "testing",
        "AWS_SECURITY_TOKEN": "testing",
        "AWS_SESSION_TOKEN": "testing",
    }
    for k, v in {**defaults, **overrides}.items():
        monkeypatch.setenv(k, v)

    spec = importlib.util.spec_from_file_location("inspector_fp", _LAMBDA_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    mod.ec2_client = boto3.client("ec2", region_name="us-east-1")
    mod.sns_client = boto3.client("sns", region_name="us-east-1")
    mod.inspector2_client = boto3.client("inspector2", region_name="us-east-1")
    return mod


def _ec2_event(severity="HIGH", instance_id="i-1234567890abcdef0"):
    return {
        "version": "0",
        "source": "aws.inspector2",
        "account": "123456789012",
        "region": "us-east-1",
        "detail-type": "Inspector2 Finding",
        "detail": {
            "findingArn": "arn:aws:inspector2:us-east-1:123456789012:finding/abc123",
            "type": "PACKAGE_VULNERABILITY",
            "severity": severity,
            "title": "CVE-2021-44228 - Log4Shell",
            "description": "Critical RCE in Apache Log4j.",
            "awsAccountId": "123456789012",
            "resourceType": "AWS_EC2_INSTANCE",
            "resourceDetails": {
                "awsEc2Instance": {"instanceId": instance_id}
            },
            "packageVulnerabilityDetails": {
                "vulnerabilityId": "CVE-2021-44228",
                "cvss": [{"baseScore": 10.0}],
                "vulnerablePackages": [{"name": "log4j-core", "version": "2.14.1"}],
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
            result = m.parse_finding(_ec2_event())
        assert result["finding_arn"].startswith("arn:aws:inspector2")
        assert result["finding_type"] == "PACKAGE_VULNERABILITY"
        assert result["severity_label"] == "HIGH"
        assert result["severity"] == 7.5
        assert result["resource"]["instanceId"] == "i-1234567890abcdef0"
        assert result["package_vulnerability"]["vulnerability_id"] == "CVE-2021-44228"
        assert result["package_vulnerability"]["cvss_score"] == 10.0

    def test_severity_critical_maps_to_9_5(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(_ec2_event(severity="CRITICAL"))
        assert result["severity"] == 9.5

    def test_severity_medium_maps_to_5_0(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(_ec2_event(severity="MEDIUM"))
        assert result["severity"] == 5.0

    def test_severity_low_maps_to_2_0(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(_ec2_event(severity="LOW"))
        assert result["severity"] == 2.0

    def test_severity_informational_maps_to_0_5(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(_ec2_event(severity="INFORMATIONAL"))
        assert result["severity"] == 0.5

    def test_missing_detail_returns_empty_defaults(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding({})
        assert result is not None
        assert result["title"] == "Unknown Finding"
        # No severity key → defaults to INFORMATIONAL → 0.5 per severity_map
        assert result["severity"] == 0.5

    def test_none_event_returns_none(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(None)
        assert result is None

    def test_account_id_falls_back_to_event_account(self, monkeypatch):
        event = {"account": "999888777666", "detail": {}}
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(event)
        assert result["aws_account_id"] == "999888777666"

    def test_multiple_cvss_scores_takes_max(self, monkeypatch):
        event = _ec2_event()
        event["detail"]["packageVulnerabilityDetails"]["cvss"] = [
            {"baseScore": 5.0}, {"baseScore": 9.8}, {"baseScore": 7.2}
        ]
        with mock_aws():
            m = _load(monkeypatch)
            result = m.parse_finding(event)
        assert result["package_vulnerability"]["cvss_score"] == 9.8


# ---------------------------------------------------------------------------
# get_severity_label
# ---------------------------------------------------------------------------

class TestGetSeverityLabel:
    def test_9_or_above_is_critical(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
        assert m.get_severity_label(9.0) == "CRITICAL"
        assert m.get_severity_label(10.0) == "CRITICAL"

    def test_7_to_8_9_is_high(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
        assert m.get_severity_label(7.0) == "HIGH"
        assert m.get_severity_label(8.9) == "HIGH"

    def test_4_to_6_9_is_medium(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
        assert m.get_severity_label(4.0) == "MEDIUM"
        assert m.get_severity_label(6.9) == "MEDIUM"

    def test_1_to_3_9_is_low(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
        assert m.get_severity_label(1.0) == "LOW"
        assert m.get_severity_label(3.9) == "LOW"

    def test_below_1_is_informational(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
        assert m.get_severity_label(0.0) == "INFORMATIONAL"
        assert m.get_severity_label(0.9) == "INFORMATIONAL"


# ---------------------------------------------------------------------------
# tag_instance
# ---------------------------------------------------------------------------

class TestTagInstance:
    def _finding(self, instance_id="i-abc"):
        return {
            "finding_arn": "arn:...",
            "finding_type": "PACKAGE_VULNERABILITY",
            "severity": 7.5,
            "severity_label": "HIGH",
            "title": "Test",
            "resource": {"instanceId": instance_id},
            "package_vulnerability": {"vulnerability_id": "CVE-2021-44228", "cvss_score": 10.0},
        }

    def test_no_instance_id_returns_none(self, monkeypatch):
        finding = self._finding(instance_id="")
        with mock_aws():
            m = _load(monkeypatch)
            result = m.tag_instance(finding)
        assert result is None

    def test_successful_tag_returns_success_dict(self, monkeypatch):
        with mock_aws():
            ec2 = boto3.client("ec2", region_name="us-east-1")
            vpc = ec2.create_vpc(CidrBlock="10.0.0.0/16")
            subnet = ec2.create_subnet(VpcId=vpc["Vpc"]["VpcId"], CidrBlock="10.0.1.0/24")
            instance_id = ec2.run_instances(
                ImageId="ami-12345678", MinCount=1, MaxCount=1,
                SubnetId=subnet["Subnet"]["SubnetId"]
            )["Instances"][0]["InstanceId"]

            m = _load(monkeypatch)
            m.ec2_client = ec2
            result = m.tag_instance(self._finding(instance_id=instance_id))

        assert result["status"] == "SUCCESS"
        assert result["action"] == "TAG_INSTANCE"
        assert result["instance_id"] == instance_id
        assert len(result["tags_applied"]) == 4
        assert "InspectorSeverity" in result["tags_applied"]
        assert "InspectorVulnerabilityId" in result["tags_applied"]

    def test_client_error_returns_failed_dict(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            with patch.object(m.ec2_client, "create_tags",
                              side_effect=ClientError({"Error": {"Code": "InvalidInstanceID.NotFound", "Message": "x"}}, "CreateTags")):
                result = m.tag_instance(self._finding(instance_id="i-bad"))
        assert result["status"] == "FAILED"
        assert "error" in result


# ---------------------------------------------------------------------------
# send_notification (Inspector)
# ---------------------------------------------------------------------------

class TestSendNotification:
    def _finding(self):
        return {
            "finding_arn": "arn:...",
            "finding_type": "PACKAGE_VULNERABILITY",
            "severity": 7.5,
            "severity_label": "HIGH",
            "title": "CVE test",
            "description": "A test vulnerability.",
            "aws_account_id": "123456789012",
            "region": "us-east-1",
            "resource": {"instanceId": "i-abc"},
            "package_vulnerability": {"vulnerability_id": "CVE-2021-44228", "cvss_score": 10.0},
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
            arn = sns.create_topic(Name="alerts")["TopicArn"]
            m = _load(monkeypatch, SNS_TOPIC_ARN=arn)
            m.sns_client = sns
            m.send_notification(self._finding(), [])  # should not raise

    def test_sns_error_does_not_raise(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:nonexistent")
            m.send_notification(self._finding(), [])  # should not raise


# ---------------------------------------------------------------------------
# process_finding
# ---------------------------------------------------------------------------

class TestProcessFinding:
    def _finding(self, severity=7.5):
        return {
            "finding_arn": "arn:...",
            "finding_type": "PACKAGE_VULNERABILITY",
            "severity": severity,
            "severity_label": "HIGH",
            "title": "Test",
            "description": "",
            "aws_account_id": "123456789012",
            "region": "us-east-1",
            "resource": {"instanceId": "i-abc"},
            "package_vulnerability": {"vulnerability_id": "CVE-X", "cvss_score": 7.5},
        }

    def test_below_threshold_no_tagging_no_notification(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, SEVERITY_THRESHOLD="7.0")
            with patch.object(m, "tag_instance") as mock_tag, \
                 patch.object(m, "send_notification") as mock_notify:
                result = m.process_finding(self._finding(severity=6.9))
            mock_tag.assert_not_called()
            mock_notify.assert_not_called()
        assert result == []

    def test_above_threshold_tags_and_notifies(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, SEVERITY_THRESHOLD="7.0", TAG_INSTANCES="true")
            with patch.object(m, "tag_instance", return_value={"action": "TAG_INSTANCE", "status": "SUCCESS"}) as mock_tag, \
                 patch.object(m, "send_notification") as mock_notify:
                result = m.process_finding(self._finding(severity=8.0))
            mock_tag.assert_called_once()
            mock_notify.assert_called_once()
        assert len(result) == 1

    def test_tag_instances_false_skips_tagging(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch, SEVERITY_THRESHOLD="7.0", TAG_INSTANCES="false")
            with patch.object(m, "tag_instance") as mock_tag, \
                 patch.object(m, "send_notification"):
                m.process_finding(self._finding(severity=8.0))
            mock_tag.assert_not_called()


# ---------------------------------------------------------------------------
# lambda_handler (Inspector)
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
                result = m.lambda_handler(_ec2_event(severity="HIGH"), None)
            mock_proc.assert_called_once()
        assert result["statusCode"] == 200

    def test_body_is_valid_json(self, monkeypatch):
        with mock_aws():
            m = _load(monkeypatch)
            with patch.object(m, "process_finding", return_value=[]):
                result = m.lambda_handler(_ec2_event(), None)
        body = json.loads(result["body"])
        assert "message" in body
        assert "actions" in body
        assert "timestamp" in body
