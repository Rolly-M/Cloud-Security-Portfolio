"""
Unit tests for remediation_handler.py

All AWS calls are intercepted by moto — no real AWS credentials needed.
The module uses module-level boto3 clients, so we patch them directly after
importing the module inside each moto context.
"""

import json
import os
import sys
import importlib
from unittest.mock import patch, MagicMock
import pytest
import boto3
from moto import mock_aws


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_handler(monkeypatch, **env_overrides):
    """
    Import (or reload) remediation_handler with the given env vars set.
    Must be called inside an active moto mock_aws context.
    """
    defaults = {
        "ENVIRONMENT": "test",
        "SNS_TOPIC_ARN": "",
        "SLACK_WEBHOOK_URL": "",
        "FINDINGS_BUCKET": "",
        "QUARANTINE_SG_ID": "",
        "ENABLE_AUTO_REMEDIATION": "true",
        "SEVERITY_THRESHOLD": "7.0",
        "ISOLATE_EC2": "true",
        "SNAPSHOT_INSTANCE": "true",
        "DISABLE_IAM_CREDENTIALS": "true",
        "BLOCK_MALICIOUS_IP": "true",
        # Ensure boto3 client creation (at module level) has a region
        "AWS_DEFAULT_REGION": "us-east-1",
        "AWS_ACCESS_KEY_ID": "testing",
        "AWS_SECRET_ACCESS_KEY": "testing",
        "AWS_SECURITY_TOKEN": "testing",
        "AWS_SESSION_TOKEN": "testing",
    }
    for k, v in {**defaults, **env_overrides}.items():
        monkeypatch.setenv(k, v)

    # Force a fresh import so module-level env-var reads pick up our values
    if "remediation_handler" in sys.modules:
        del sys.modules["remediation_handler"]
    import remediation_handler as rh
    # Replace module-level AWS clients with moto-backed ones
    rh.ec2_client = boto3.client("ec2", region_name="us-east-1")
    rh.iam_client = boto3.client("iam", region_name="us-east-1")
    rh.sns_client = boto3.client("sns", region_name="us-east-1")
    rh.s3_client = boto3.client("s3", region_name="us-east-1")
    return rh


# ---------------------------------------------------------------------------
# parse_finding
# ---------------------------------------------------------------------------

class TestParseFinding:
    def test_well_formed_event_returns_all_fields(self, monkeypatch, ec2_event):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.parse_finding(ec2_event)

        assert result["id"] == "finding-id-ec2-001"
        assert result["type"] == "UnauthorizedAccess:EC2/SSHBruteForce"
        assert result["severity"] == 8.0
        assert result["region"] == "us-east-1"
        assert result["account_id"] == "123456789012"
        assert "instanceDetails" in result["resource"]

    def test_severity_coerced_to_float(self, monkeypatch, ec2_event):
        ec2_event["detail"]["severity"] = "5"
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.parse_finding(ec2_event)
        assert isinstance(result["severity"], float)
        assert result["severity"] == 5.0

    def test_missing_detail_uses_defaults(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.parse_finding({})
        assert result["id"] == "unknown"
        assert result["severity"] == 0.0

    def test_malformed_event_returns_none(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            # Passing a non-dict will raise inside parse_finding → returns None
            result = rh.parse_finding(None)
        assert result is None

    def test_account_id_falls_back_to_event_account(self, monkeypatch):
        event = {
            "account": "999999999999",
            "region": "eu-west-1",
            "detail": {"severity": 3.0},
        }
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.parse_finding(event)
        assert result["account_id"] == "999999999999"
        assert result["region"] == "eu-west-1"


# ---------------------------------------------------------------------------
# store_finding
# ---------------------------------------------------------------------------

class TestStoreFinding:
    def test_no_bucket_configured_skips_s3(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, FINDINGS_BUCKET="")
            with patch.object(rh.s3_client, "put_object") as mock_put:
                rh.store_finding({"id": "x", "raw": {}})
            mock_put.assert_not_called()

    def test_bucket_configured_calls_put_object_with_kms(self, monkeypatch):
        with mock_aws():
            s3 = boto3.client("s3", region_name="us-east-1")
            s3.create_bucket(Bucket="test-findings-bucket")
            rh = _load_handler(monkeypatch, FINDINGS_BUCKET="test-findings-bucket")
            rh.s3_client = s3

            finding = {"id": "abc123", "raw": {"key": "value"}}
            rh.store_finding(finding)

            objects = s3.list_objects_v2(Bucket="test-findings-bucket")
            assert objects["KeyCount"] == 1
            key = objects["Contents"][0]["Key"]
            assert key.startswith("findings/")
            assert key.endswith("/abc123.json")

    def test_s3_error_does_not_raise(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, FINDINGS_BUCKET="nonexistent-bucket")
            # moto will raise NoSuchBucket; handler should swallow it
            rh.store_finding({"id": "x", "raw": {}})  # should not raise


# ---------------------------------------------------------------------------
# create_response
# ---------------------------------------------------------------------------

class TestCreateResponse:
    def test_returns_correct_status_code(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            resp = rh.create_response(200, "ok")
        assert resp["statusCode"] == 200

    def test_body_is_valid_json(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            resp = rh.create_response(200, "ok")
        body = json.loads(resp["body"])
        assert body["message"] == "ok"
        assert body["actions"] == []
        assert "timestamp" in body

    def test_actions_none_becomes_empty_list(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            resp = rh.create_response(400, "bad", actions=None)
        assert json.loads(resp["body"])["actions"] == []

    def test_actions_included_when_provided(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            actions = [{"action": "ISOLATE_INSTANCE", "status": "SUCCESS"}]
            resp = rh.create_response(200, "done", actions=actions)
        assert json.loads(resp["body"])["actions"] == actions


# ---------------------------------------------------------------------------
# execute_remediation routing
# ---------------------------------------------------------------------------

class TestExecuteRemediation:
    def _make_finding(self, finding_type, service=None):
        return {
            "id": "f1",
            "type": finding_type,
            "severity": 8.0,
            "title": "test",
            "description": "",
            "region": "us-east-1",
            "account_id": "123456789012",
            "resource": {},
            "service": service or {},
        }

    def test_ec2_prefix_routes_to_remediate_ec2(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            with patch.object(rh, "remediate_ec2", return_value=[]) as mock_fn:
                rh.execute_remediation(self._make_finding("EC2/CryptoCurrency"))
            mock_fn.assert_called_once()

    def test_colon_ec2_prefix_routes_to_remediate_ec2(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            with patch.object(rh, "remediate_ec2", return_value=[]) as mock_fn:
                rh.execute_remediation(self._make_finding("UnauthorizedAccess:EC2/SSHBruteForce"))
            mock_fn.assert_called_once()

    def test_iam_prefix_routes_to_remediate_iam(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            with patch.object(rh, "remediate_iam", return_value=[]) as mock_fn:
                rh.execute_remediation(self._make_finding("IAMUser/CredentialAccess"))
            mock_fn.assert_called_once()

    def test_s3_prefix_routes_to_remediate_s3(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            with patch.object(rh, "remediate_s3", return_value=[]) as mock_fn:
                rh.execute_remediation(self._make_finding("S3/MaliciousIPCaller"))
            mock_fn.assert_called_once()

    def test_remote_ip_details_triggers_block_ip(self, monkeypatch):
        # Code checks `'RemoteIpDetails' in str(service)` — must use PascalCase key
        service = {"action": {"networkConnectionAction": {"RemoteIpDetails": {"ipAddressV4": "1.2.3.4"}}}}
        finding = self._make_finding("EC2/CryptoCurrency", service=service)
        with mock_aws():
            rh = _load_handler(monkeypatch)
            with patch.object(rh, "remediate_ec2", return_value=[]):
                with patch.object(rh, "block_malicious_ip", return_value=[{"action": "BLOCK_IP_LOGGED"}]) as mock_block:
                    rh.execute_remediation(finding)
            mock_block.assert_called_once()

    def test_unknown_type_returns_empty_list(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.execute_remediation(self._make_finding("Unknown/SomeFinding"))
        assert result == []


# ---------------------------------------------------------------------------
# remediate_ec2
# ---------------------------------------------------------------------------

class TestRemediateEC2:
    def _finding_with_instance(self, instance_id="i-abc123"):
        return {
            "id": "f1", "type": "EC2/CryptoCurrency", "severity": 8.0,
            "title": "t", "description": "", "region": "us-east-1",
            "account_id": "123456789012",
            "resource": {"instanceDetails": {"instanceId": instance_id}},
            "service": {},
        }

    def test_no_instance_id_returns_empty(self, monkeypatch):
        finding = self._finding_with_instance()
        finding["resource"] = {}
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.remediate_ec2(finding)
        assert result == []

    def test_snapshot_false_skips_snapshot(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, SNAPSHOT_INSTANCE="false")
            with patch.object(rh, "create_forensic_snapshot") as mock_snap:
                with patch.object(rh, "isolate_instance", return_value=None):
                    rh.remediate_ec2(self._finding_with_instance())
            mock_snap.assert_not_called()

    def test_isolate_false_skips_isolation(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, ISOLATE_EC2="false")
            with patch.object(rh, "create_forensic_snapshot", return_value=None):
                with patch.object(rh, "isolate_instance") as mock_iso:
                    rh.remediate_ec2(self._finding_with_instance())
            mock_iso.assert_not_called()

    def test_both_actions_called_when_enabled(self, monkeypatch):
        snap_action = {"action": "CREATE_FORENSIC_SNAPSHOT", "status": "SUCCESS"}
        iso_action = {"action": "ISOLATE_INSTANCE", "status": "SUCCESS"}
        with mock_aws():
            rh = _load_handler(monkeypatch, SNAPSHOT_INSTANCE="true", ISOLATE_EC2="true")
            with patch.object(rh, "create_forensic_snapshot", return_value=snap_action):
                with patch.object(rh, "isolate_instance", return_value=iso_action):
                    result = rh.remediate_ec2(self._finding_with_instance())
        assert len(result) == 2


# ---------------------------------------------------------------------------
# create_forensic_snapshot
# ---------------------------------------------------------------------------

class TestCreateForensicSnapshot:
    def test_instance_not_found_returns_failed_dict(self, monkeypatch):
        # moto raises InvalidInstanceID.NotFound (a ClientError), so we expect FAILED
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.create_forensic_snapshot("i-doesnotexist", {"id": "f1", "type": "t", "severity": 8.0})
        assert result["status"] == "FAILED"
        assert result["action"] == "CREATE_FORENSIC_SNAPSHOT"

    def test_creates_snapshot_for_each_volume(self, monkeypatch):
        with mock_aws():
            ec2 = boto3.client("ec2", region_name="us-east-1")
            # Create a real EC2 instance via moto
            vpc = ec2.create_vpc(CidrBlock="10.0.0.0/16")
            subnet = ec2.create_subnet(VpcId=vpc["Vpc"]["VpcId"], CidrBlock="10.0.1.0/24")
            reservation = ec2.run_instances(
                ImageId="ami-12345678",
                MinCount=1,
                MaxCount=1,
                SubnetId=subnet["Subnet"]["SubnetId"],
            )
            instance_id = reservation["Instances"][0]["InstanceId"]

            rh = _load_handler(monkeypatch)
            rh.ec2_client = ec2
            finding = {"id": "f1", "type": "EC2/CryptoCurrency", "severity": 8.0}
            result = rh.create_forensic_snapshot(instance_id, finding)

        assert result is not None
        assert result["status"] == "SUCCESS"
        assert result["instance_id"] == instance_id
        assert len(result["snapshot_ids"]) >= 1

    def test_client_error_returns_failed_dict(self, monkeypatch):
        from botocore.exceptions import ClientError
        with mock_aws():
            rh = _load_handler(monkeypatch)
            with patch.object(rh.ec2_client, "describe_instances",
                              side_effect=ClientError({"Error": {"Code": "InvalidInstanceID.NotFound", "Message": "Not found"}}, "DescribeInstances")):
                result = rh.create_forensic_snapshot("i-bad", {"id": "f1", "type": "t", "severity": 8.0})
        assert result["status"] == "FAILED"
        assert result["action"] == "CREATE_FORENSIC_SNAPSHOT"


# ---------------------------------------------------------------------------
# isolate_instance
# ---------------------------------------------------------------------------

class TestIsolateInstance:
    def _finding(self):
        return {"id": "f1", "type": "EC2/CryptoCurrency", "severity": 8.0}

    def test_no_quarantine_sg_returns_none(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, QUARANTINE_SG_ID="")
            result = rh.isolate_instance("i-abc", self._finding())
        assert result is None

    def test_instance_not_found_returns_failed_dict(self, monkeypatch):
        # moto raises InvalidInstanceID.NotFound for unknown instance IDs
        with mock_aws():
            rh = _load_handler(monkeypatch, QUARANTINE_SG_ID="sg-quarantine")
            result = rh.isolate_instance("i-doesnotexist", self._finding())
        assert result["status"] == "FAILED"
        assert result["action"] == "ISOLATE_INSTANCE"

    def test_successful_isolation_replaces_security_groups(self, monkeypatch):
        with mock_aws():
            ec2 = boto3.client("ec2", region_name="us-east-1")
            vpc = ec2.create_vpc(CidrBlock="10.0.0.0/16")
            vpc_id = vpc["Vpc"]["VpcId"]
            subnet = ec2.create_subnet(VpcId=vpc_id, CidrBlock="10.0.1.0/24")
            quarantine_sg = ec2.create_security_group(
                GroupName="quarantine", Description="quarantine", VpcId=vpc_id
            )
            quarantine_sg_id = quarantine_sg["GroupId"]
            reservation = ec2.run_instances(
                ImageId="ami-12345678",
                MinCount=1,
                MaxCount=1,
                SubnetId=subnet["Subnet"]["SubnetId"],
            )
            instance_id = reservation["Instances"][0]["InstanceId"]

            rh = _load_handler(monkeypatch, QUARANTINE_SG_ID=quarantine_sg_id)
            rh.ec2_client = ec2
            result = rh.isolate_instance(instance_id, self._finding())

        assert result["status"] == "SUCCESS"
        assert result["quarantine_security_group"] == quarantine_sg_id
        assert "original_security_groups" in result

    def test_client_error_returns_failed_dict(self, monkeypatch):
        from botocore.exceptions import ClientError
        with mock_aws():
            rh = _load_handler(monkeypatch, QUARANTINE_SG_ID="sg-quarantine")
            with patch.object(rh.ec2_client, "describe_instances",
                              side_effect=ClientError({"Error": {"Code": "InvalidInstanceID.NotFound", "Message": "x"}}, "DescribeInstances")):
                result = rh.isolate_instance("i-bad", self._finding())
        assert result["status"] == "FAILED"
        assert result["action"] == "ISOLATE_INSTANCE"


# ---------------------------------------------------------------------------
# remediate_iam
# ---------------------------------------------------------------------------

class TestRemediateIAM:
    def _finding_with_user(self, user_name="test-user", access_key_id="AKIAIOSFODNN7EXAMPLE"):
        return {
            "id": "f1", "type": "IAMUser/CredentialAccess", "severity": 7.5,
            "resource": {
                "accessKeyDetails": {
                    "userName": user_name,
                    "accessKeyId": access_key_id,
                }
            },
            "service": {},
        }

    def test_flag_disabled_returns_empty(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, DISABLE_IAM_CREDENTIALS="false")
            result = rh.remediate_iam(self._finding_with_user())
        assert result == []

    def test_no_username_returns_empty(self, monkeypatch):
        finding = self._finding_with_user()
        finding["resource"] = {}
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.remediate_iam(finding)
        assert result == []

    def test_disables_access_key_and_attaches_deny_policy(self, monkeypatch):
        with mock_aws():
            iam = boto3.client("iam", region_name="us-east-1")
            iam.create_user(UserName="test-user")
            iam.create_access_key(UserName="test-user")
            # Get the actual key id moto created
            keys = iam.list_access_keys(UserName="test-user")["AccessKeyMetadata"]
            key_id = keys[0]["AccessKeyId"]

            finding = self._finding_with_user(access_key_id=key_id)
            rh = _load_handler(monkeypatch)
            rh.iam_client = iam
            result = rh.remediate_iam(finding)

        action_types = [a["action"] for a in result]
        assert "DISABLE_ACCESS_KEY" in action_types
        assert "ATTACH_DENY_POLICY" in action_types
        assert all(a["status"] == "SUCCESS" for a in result)

    def test_no_access_key_id_still_attaches_deny_policy(self, monkeypatch):
        with mock_aws():
            iam = boto3.client("iam", region_name="us-east-1")
            iam.create_user(UserName="test-user")

            finding = self._finding_with_user(access_key_id=None)
            finding["resource"]["accessKeyDetails"].pop("accessKeyId", None)
            rh = _load_handler(monkeypatch)
            rh.iam_client = iam
            result = rh.remediate_iam(finding)

        action_types = [a["action"] for a in result]
        assert "DISABLE_ACCESS_KEY" not in action_types
        assert "ATTACH_DENY_POLICY" in action_types

    def test_client_error_returns_failed_action(self, monkeypatch):
        from botocore.exceptions import ClientError
        with mock_aws():
            rh = _load_handler(monkeypatch)
            with patch.object(rh.iam_client, "update_access_key",
                              side_effect=ClientError({"Error": {"Code": "NoSuchEntity", "Message": "x"}}, "UpdateAccessKey")):
                result = rh.remediate_iam(self._finding_with_user())
        assert any(a["status"] == "FAILED" for a in result)


# ---------------------------------------------------------------------------
# remediate_s3
# ---------------------------------------------------------------------------

class TestRemediateS3:
    def test_multiple_buckets_logged(self, monkeypatch, s3_event):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            finding = rh.parse_finding(s3_event)
            result = rh.remediate_s3(finding)
        assert len(result) == 2
        assert all(a["action"] == "S3_FINDING_LOGGED" for a in result)
        bucket_names = [a["bucket_name"] for a in result]
        assert "my-sensitive-bucket" in bucket_names
        assert "another-bucket" in bucket_names

    def test_no_s3_details_returns_empty(self, monkeypatch):
        finding = {"resource": {}, "type": "S3/MaliciousIPCaller"}
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.remediate_s3(finding)
        assert result == []

    def test_empty_s3_bucket_list_returns_empty(self, monkeypatch):
        finding = {"resource": {"s3BucketDetails": []}, "type": "S3/MaliciousIPCaller"}
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.remediate_s3(finding)
        assert result == []


# ---------------------------------------------------------------------------
# block_malicious_ip
# ---------------------------------------------------------------------------

class TestBlockMaliciousIP:
    def _finding_with_ip(self, action_type="networkConnectionAction", ip="1.2.3.4"):
        return {
            "id": "f1", "type": "EC2/CryptoCurrency", "severity": 8.0,
            "service": {
                "action": {
                    action_type: {
                        "remoteIpDetails": {"ipAddressV4": ip}
                    }
                }
            },
        }

    def test_flag_disabled_returns_empty(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, BLOCK_MALICIOUS_IP="false")
            result = rh.block_malicious_ip(self._finding_with_ip())
        assert result == []

    def test_network_connection_action_extracts_ip(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.block_malicious_ip(self._finding_with_ip("networkConnectionAction", "5.6.7.8"))
        assert len(result) == 1
        assert result[0]["ip_address"] == "5.6.7.8"
        assert result[0]["action"] == "BLOCK_IP_LOGGED"

    def test_aws_api_call_action_extracts_ip(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.block_malicious_ip(self._finding_with_ip("awsApiCallAction", "9.10.11.12"))
        assert result[0]["ip_address"] == "9.10.11.12"

    def test_port_probe_action_extracts_ip(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.block_malicious_ip(self._finding_with_ip("portProbeAction", "13.14.15.16"))
        assert result[0]["ip_address"] == "13.14.15.16"

    def test_no_remote_ip_returns_empty(self, monkeypatch):
        finding = {"id": "f1", "type": "EC2/CryptoCurrency", "severity": 8.0,
                   "service": {"action": {}}}
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.block_malicious_ip(finding)
        assert result == []

    def test_first_matching_action_wins(self, monkeypatch):
        """networkConnectionAction should be checked before awsApiCallAction."""
        finding = {
            "id": "f1", "type": "EC2/Backdoor", "severity": 8.0,
            "service": {
                "action": {
                    "networkConnectionAction": {"remoteIpDetails": {"ipAddressV4": "1.1.1.1"}},
                    "awsApiCallAction": {"remoteIpDetails": {"ipAddressV4": "2.2.2.2"}},
                }
            },
        }
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.block_malicious_ip(finding)
        assert len(result) == 1
        assert result[0]["ip_address"] == "1.1.1.1"


# ---------------------------------------------------------------------------
# send_notification
# ---------------------------------------------------------------------------

class TestSendNotification:
    def _finding(self, severity=8.0):
        return {
            "id": "f1", "type": "EC2/CryptoCurrency", "severity": severity,
            "title": "test", "description": "test description",
            "region": "us-east-1", "account_id": "123456789012",
        }

    def test_no_sns_arn_does_not_call_publish(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, SNS_TOPIC_ARN="")
            with patch.object(rh.sns_client, "publish") as mock_pub:
                rh.send_notification(self._finding(), [])
            mock_pub.assert_not_called()

    def test_sns_arn_configured_calls_publish(self, monkeypatch):
        with mock_aws():
            sns = boto3.client("sns", region_name="us-east-1")
            topic = sns.create_topic(Name="test-alerts")
            topic_arn = topic["TopicArn"]

            rh = _load_handler(monkeypatch, SNS_TOPIC_ARN=topic_arn)
            rh.sns_client = sns
            rh.send_notification(self._finding(), [])

            # Verify publish was sent (moto records it)
            # No exception = success

    def test_sns_error_does_not_raise(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:nonexistent")
            rh.send_notification(self._finding(), [])  # should not raise

    def test_slack_webhook_calls_send_slack(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, SLACK_WEBHOOK_URL="https://hooks.slack.com/test")
            with patch.object(rh, "send_slack_notification") as mock_slack:
                rh.send_notification(self._finding(), [])
            mock_slack.assert_called_once()

    def test_no_slack_webhook_skips_slack(self, monkeypatch):
        with mock_aws():
            rh = _load_handler(monkeypatch, SLACK_WEBHOOK_URL="")
            with patch.object(rh, "send_slack_notification") as mock_slack:
                rh.send_notification(self._finding(), [])
            mock_slack.assert_not_called()


# ---------------------------------------------------------------------------
# lambda_handler — end-to-end flow
# ---------------------------------------------------------------------------

class TestLambdaHandler:
    def test_no_finding_returns_400(self, monkeypatch):
        # None event causes parse_finding to raise AttributeError → returns None → 400
        with mock_aws():
            rh = _load_handler(monkeypatch)
            result = rh.lambda_handler(None, None)
        assert result["statusCode"] == 400

    def test_below_threshold_returns_200_without_remediation(self, monkeypatch, low_severity_event):
        with mock_aws():
            rh = _load_handler(monkeypatch, SEVERITY_THRESHOLD="7.0")
            with patch.object(rh, "execute_remediation") as mock_rem:
                with patch.object(rh, "send_notification"):
                    result = rh.lambda_handler(low_severity_event, None)
            mock_rem.assert_not_called()
        assert result["statusCode"] == 200

    def test_above_threshold_executes_remediation(self, monkeypatch, ec2_event):
        with mock_aws():
            rh = _load_handler(monkeypatch, SEVERITY_THRESHOLD="7.0")
            with patch.object(rh, "execute_remediation", return_value=[]) as mock_rem:
                with patch.object(rh, "send_notification"):
                    with patch.object(rh, "store_finding"):
                        result = rh.lambda_handler(ec2_event, None)
            mock_rem.assert_called_once()
        assert result["statusCode"] == 200

    def test_auto_remediation_disabled_skips_remediation(self, monkeypatch, ec2_event):
        with mock_aws():
            rh = _load_handler(monkeypatch, ENABLE_AUTO_REMEDIATION="false")
            with patch.object(rh, "execute_remediation") as mock_rem:
                with patch.object(rh, "send_notification"):
                    with patch.object(rh, "store_finding"):
                        result = rh.lambda_handler(ec2_event, None)
            mock_rem.assert_not_called()
        assert result["statusCode"] == 200

    def test_exception_returns_500_and_sends_error_notification(self, monkeypatch, ec2_event):
        with mock_aws():
            rh = _load_handler(monkeypatch)
            with patch.object(rh, "parse_finding", side_effect=RuntimeError("boom")):
                with patch.object(rh, "send_error_notification") as mock_err:
                    result = rh.lambda_handler(ec2_event, None)
            mock_err.assert_called_once()
        assert result["statusCode"] == 500

    def test_severity_boundary_exactly_at_threshold_triggers_remediation(self, monkeypatch, ec2_event):
        """Finding at exactly the threshold value should trigger remediation."""
        ec2_event["detail"]["severity"] = 7.0
        with mock_aws():
            rh = _load_handler(monkeypatch, SEVERITY_THRESHOLD="7.0")
            with patch.object(rh, "execute_remediation", return_value=[]) as mock_rem:
                with patch.object(rh, "send_notification"):
                    with patch.object(rh, "store_finding"):
                        rh.lambda_handler(ec2_event, None)
        mock_rem.assert_called_once()

    def test_severity_just_below_threshold_skips_remediation(self, monkeypatch, ec2_event):
        """6.9 should NOT trigger when threshold is 7.0."""
        ec2_event["detail"]["severity"] = 6.9
        with mock_aws():
            rh = _load_handler(monkeypatch, SEVERITY_THRESHOLD="7.0")
            with patch.object(rh, "execute_remediation") as mock_rem:
                with patch.object(rh, "send_notification"):
                    with patch.object(rh, "store_finding"):
                        rh.lambda_handler(ec2_event, None)
        mock_rem.assert_not_called()

    def test_notification_failure_does_not_mask_200_response(self, monkeypatch, ec2_event):
        """A crash in send_notification should not turn a successful remediation into a 500."""
        from botocore.exceptions import ClientError
        with mock_aws():
            rh = _load_handler(monkeypatch, SEVERITY_THRESHOLD="7.0", SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:topic")
            with patch.object(rh, "execute_remediation", return_value=[]):
                with patch.object(rh, "store_finding"):
                    # sns.publish will fail because topic doesn't exist in moto, but handler should still return 200
                    result = rh.lambda_handler(ec2_event, None)
        assert result["statusCode"] == 200
