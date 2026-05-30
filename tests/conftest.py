import json
import os
import sys
import pytest
import boto3
from moto import mock_aws

# Make the lambda source importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "2 - AWS_Guard_Duty", "lambda"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "2 - AWS_Guard_Duty", "threat-simulation"))

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures")


@pytest.fixture
def sample_events():
    with open(os.path.join(FIXTURES_DIR, "sample_events.json")) as f:
        return json.load(f)


@pytest.fixture
def ec2_event(sample_events):
    return sample_events["ec2_finding"]


@pytest.fixture
def iam_event(sample_events):
    return sample_events["iam_finding"]


@pytest.fixture
def s3_event(sample_events):
    return sample_events["s3_finding"]


@pytest.fixture
def low_severity_event(sample_events):
    return sample_events["low_severity_finding"]


@pytest.fixture
def base_env(monkeypatch):
    """Minimal environment with no optional integrations enabled."""
    monkeypatch.setenv("ENVIRONMENT", "test")
    monkeypatch.setenv("SNS_TOPIC_ARN", "")
    monkeypatch.setenv("SLACK_WEBHOOK_URL", "")
    monkeypatch.setenv("FINDINGS_BUCKET", "")
    monkeypatch.setenv("QUARANTINE_SG_ID", "")
    monkeypatch.setenv("ENABLE_AUTO_REMEDIATION", "true")
    monkeypatch.setenv("SEVERITY_THRESHOLD", "7.0")
    monkeypatch.setenv("ISOLATE_EC2", "true")
    monkeypatch.setenv("SNAPSHOT_INSTANCE", "true")
    monkeypatch.setenv("DISABLE_IAM_CREDENTIALS", "true")
    monkeypatch.setenv("BLOCK_MALICIOUS_IP", "true")


@pytest.fixture
def aws_credentials():
    """Mocked AWS credentials so moto intercepts all boto3 calls."""
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_SECURITY_TOKEN"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
