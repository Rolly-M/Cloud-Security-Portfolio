"""
AWS Inspector v2 Finding Processor

This Lambda function processes Inspector v2 findings delivered via EventBridge by:
1. Parsing finding details (severity, CVE, affected packages, resource)
2. Tagging affected EC2 instances with finding metadata
3. Sending structured notifications via SNS for HIGH/CRITICAL findings

Author: Cloud Security Portfolio
Version: 1.0.0
"""

import json
import os
import logging
import boto3
from botocore.exceptions import ClientError
from datetime import datetime, timezone

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Module-level boto3 clients (replaced in unit tests)
ec2_client = boto3.client('ec2')
sns_client = boto3.client('sns')
inspector2_client = boto3.client('inspector2')

# Environment variables read at module level
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
SEVERITY_THRESHOLD = float(os.environ.get('SEVERITY_THRESHOLD', '7.0'))
TAG_INSTANCES = os.environ.get('TAG_INSTANCES', 'true').lower() == 'true'


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def lambda_handler(event, context):
    """
    Main Lambda handler — receives EventBridge events from Inspector v2.

    Returns a standardised response dict with statusCode and JSON body.
    """
    logger.info(f"Received Inspector v2 event: {json.dumps(event)}")

    finding = parse_finding(event)

    if not finding:
        logger.warning("No valid finding could be parsed from the event")
        return create_response(400, "No valid finding in event")

    actions_taken = process_finding(finding)

    return create_response(200, "Finding processed successfully", actions_taken)


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def parse_finding(event):
    """
    Extract a normalised finding dict from an EventBridge Inspector2 event.

    Returns None when the event cannot be parsed.
    """
    try:
        detail = event.get('detail', {})

        # Resource details — Inspector v2 findings always carry a resourceDetails
        # block; for EC2 findings the instanceId lives under awsEc2Instance.
        resource_details = detail.get('resourceDetails', {})
        ec2_details = resource_details.get('awsEc2Instance', {})
        resource = {
            'instanceId': ec2_details.get('instanceId', ''),
            'type': detail.get('resourceType', ''),
        }

        # Package vulnerability details
        package_vuln = detail.get('packageVulnerabilityDetails', {})
        cvss_list = package_vuln.get('cvss', [])
        cvss_score = max((c.get('baseScore', 0.0) for c in cvss_list), default=0.0)
        package_vulnerability = {
            'vulnerability_id': package_vuln.get('vulnerabilityId', ''),
            'cvss_score': cvss_score,
            'packages': package_vuln.get('vulnerablePackages', []),
        }

        # Network reachability details
        network_detail = detail.get('networkReachabilityDetails', {})
        open_port_range = network_detail.get('openPortRange', {})
        network_reachability = {
            'open_port_range': open_port_range,
        }

        # Inspector v2 severity label → numeric mapping used throughout
        severity_label = detail.get('severity', 'INFORMATIONAL')
        severity_map = {
            'CRITICAL': 9.5,
            'HIGH': 7.5,
            'MEDIUM': 5.0,
            'LOW': 2.0,
            'INFORMATIONAL': 0.5,
        }
        severity = severity_map.get(severity_label.upper(), 0.0)

        return {
            'finding_arn': detail.get('findingArn', ''),
            'finding_type': detail.get('type', ''),
            'severity': severity,
            'severity_label': severity_label,
            'title': detail.get('title', 'Unknown Finding'),
            'description': detail.get('description', ''),
            'aws_account_id': detail.get('awsAccountId', event.get('account', '')),
            'region': event.get('region', detail.get('resources', [{}])[0].get('region', '')),
            'resource': resource,
            'package_vulnerability': package_vulnerability,
            'network_reachability': network_reachability,
        }

    except Exception as e:
        logger.error(f"Error parsing Inspector v2 finding: {e}", exc_info=True)
        return None


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def process_finding(finding):
    """
    Orchestrate logging, tagging, and notification for a parsed finding.

    Returns a list of action dicts describing what was done.
    """
    actions_taken = []

    log_finding(finding)

    if finding['severity'] >= SEVERITY_THRESHOLD:
        if TAG_INSTANCES:
            tag_action = tag_instance(finding)
            if tag_action:
                actions_taken.append(tag_action)

        send_notification(finding, actions_taken)

    return actions_taken


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

def log_finding(finding):
    """Log structured finding details for audit and observability."""
    logger.info("=" * 60)
    logger.info("INSPECTOR v2 FINDING DETECTED")
    logger.info("=" * 60)
    logger.info(f"Finding ARN:   {finding['finding_arn']}")
    logger.info(f"Type:          {finding['finding_type']}")
    logger.info(f"Severity:      {finding['severity_label']} ({finding['severity']})")
    logger.info(f"Title:         {finding['title']}")
    logger.info(f"Account:       {finding['aws_account_id']}")
    logger.info(f"Region:        {finding['region']}")
    logger.info(f"Instance ID:   {finding['resource'].get('instanceId', 'N/A')}")
    logger.info(f"CVE/Vuln ID:   {finding['package_vulnerability'].get('vulnerability_id', 'N/A')}")
    logger.info(f"CVSS Score:    {finding['package_vulnerability'].get('cvss_score', 'N/A')}")
    logger.info("=" * 60)


# ---------------------------------------------------------------------------
# Instance tagging
# ---------------------------------------------------------------------------

def tag_instance(finding):
    """
    Apply Inspector finding metadata tags to the affected EC2 instance.

    Returns an action dict on success/failure, or None if no instance ID.
    """
    instance_id = finding['resource'].get('instanceId', '')
    if not instance_id:
        logger.warning("tag_instance: no instanceId in finding resource — skipping")
        return None

    vuln_id = finding['package_vulnerability'].get('vulnerability_id', '')
    now_iso = datetime.now(timezone.utc).isoformat()

    tags = [
        {'Key': 'InspectorSeverity',        'Value': finding['severity_label']},
        {'Key': 'InspectorFindingType',     'Value': finding['finding_type']},
        {'Key': 'InspectorVulnerabilityId', 'Value': vuln_id},
        {'Key': 'InspectorLastScanned',     'Value': now_iso},
    ]

    try:
        ec2_client.create_tags(Resources=[instance_id], Tags=tags)
        logger.info(f"Tagged instance {instance_id} with Inspector finding metadata")
        return {
            'action': 'TAG_INSTANCE',
            'instance_id': instance_id,
            'tags_applied': [t['Key'] for t in tags],
            'status': 'SUCCESS',
        }
    except ClientError as e:
        logger.error(f"ClientError tagging instance {instance_id}: {e}")
        return {
            'action': 'TAG_INSTANCE',
            'instance_id': instance_id,
            'status': 'FAILED',
            'error': str(e),
        }


# ---------------------------------------------------------------------------
# Notification
# ---------------------------------------------------------------------------

def send_notification(finding, actions_taken):
    """
    Publish a finding summary to SNS.

    Logs errors but never re-raises so a notification failure does not
    prevent the rest of the handler from completing.
    """
    if not SNS_TOPIC_ARN:
        logger.warning("SNS_TOPIC_ARN not configured — skipping notification")
        return

    severity_label = finding['severity_label']
    instance_id = finding['resource'].get('instanceId', 'N/A')
    vuln_id = finding['package_vulnerability'].get('vulnerability_id', 'N/A')
    cvss = finding['package_vulnerability'].get('cvss_score', 'N/A')

    actions_summary = '\n'.join(
        f"  - {a.get('action')}: {a.get('status')}" for a in actions_taken
    ) or '  None'

    message = f"""Inspector v2 Security Finding — {severity_label}

Finding ARN : {finding['finding_arn']}
Type        : {finding['finding_type']}
Severity    : {severity_label} ({finding['severity']})
Title       : {finding['title']}

Account     : {finding['aws_account_id']}
Region      : {finding['region']}
Instance    : {instance_id}

Vulnerability ID : {vuln_id}
CVSS Score       : {cvss}

Description:
{finding['description'][:600]}

Actions Taken:
{actions_summary}

Environment : {ENVIRONMENT}
Timestamp   : {datetime.now(timezone.utc).isoformat()}
"""

    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[Inspector v2] {severity_label} Finding: {finding['title'][:60]}",
            Message=message,
        )
        logger.info("SNS notification published successfully")
    except Exception as e:
        logger.error(f"Failed to publish SNS notification: {e}")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def get_severity_label(severity_score):
    """
    Map a numeric CVSS / Inspector severity score to a human-readable label.

    Thresholds align with Inspector v2 severity bands.
    """
    if severity_score >= 9.0:
        return "CRITICAL"
    if severity_score >= 7.0:
        return "HIGH"
    if severity_score >= 4.0:
        return "MEDIUM"
    if severity_score >= 1.0:
        return "LOW"
    return "INFORMATIONAL"


def create_response(status_code, message, actions=None):
    """Return a standardised Lambda proxy response dict."""
    return {
        'statusCode': status_code,
        'body': json.dumps({
            'message': message,
            'actions': actions or [],
            'timestamp': datetime.now(timezone.utc).isoformat(),
        }),
    }
