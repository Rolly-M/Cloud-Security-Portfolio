"""
AWS Macie Finding Processor

This Lambda function automatically responds to Macie findings by:
1. Parsing finding details from EventBridge events
2. Quarantining objects with PII findings (copy to quarantine bucket + delete original)
3. Tagging sensitive objects with finding metadata
4. Sending SNS notifications for HIGH/CRITICAL severity findings

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

# Module-level boto3 clients
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
macie2_client = boto3.client('macie2')

# Module-level environment variables
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
QUARANTINE_BUCKET = os.environ.get('QUARANTINE_BUCKET', '')
SENSITIVE_BUCKET = os.environ.get('SENSITIVE_BUCKET', '')
ENABLE_QUARANTINE = os.environ.get('ENABLE_QUARANTINE', 'true').lower() == 'true'
SEVERITY_THRESHOLD = float(os.environ.get('SEVERITY_THRESHOLD', '7.0'))


def lambda_handler(event, context):
    """
    Main Lambda handler for Macie findings routed via EventBridge.
    """
    logger.info(f"Received event: {json.dumps(event)}")

    finding = parse_finding(event)

    if not finding:
        logger.warning("No valid finding could be parsed from event")
        return create_response(400, "No valid finding in event")

    actions = process_finding(finding)
    return create_response(200, "Finding processed successfully", actions)


def parse_finding(event):
    """
    Extract structured finding data from an EventBridge Macie event.

    Returns a dict with normalized finding fields, or None on parse failure.
    """
    try:
        detail = event.get('detail', {})

        finding_type_raw = detail.get('type', {})
        if isinstance(finding_type_raw, dict):
            finding_type = finding_type_raw.get('id', 'Unknown')
        else:
            finding_type = str(finding_type_raw) if finding_type_raw else 'Unknown'

        severity_raw = detail.get('severity', {})
        severity_score = float(severity_raw.get('score', 0)) if isinstance(severity_raw, dict) else 0.0

        resources_affected = detail.get('resourcesAffected', {})
        s3_bucket_info = resources_affected.get('s3Bucket', {})
        s3_object_info = resources_affected.get('s3Object', {})

        classification_details = detail.get('classificationDetails', {})
        result_details = classification_details.get('result', {})
        pii_types = result_details.get('sensitiveData', [])

        return {
            'finding_id': detail.get('id'),
            'finding_type': finding_type,
            'severity_score': severity_score,
            'title': detail.get('title'),
            'description': detail.get('description', ''),
            'account_id': detail.get('accountId'),
            'region': event.get('region'),
            'affected_bucket': s3_bucket_info.get('name'),
            'affected_object': s3_object_info.get('key'),
            'pii_types': pii_types,
        }
    except Exception as e:
        logger.error(f"Error parsing finding: {str(e)}", exc_info=True)
        return None


def process_finding(finding):
    """
    Evaluate a parsed finding and execute automated response actions.

    For findings at or above SEVERITY_THRESHOLD:
      - Quarantine the affected object (if enabled)
      - Tag the object with finding metadata
      - Send an SNS notification

    Returns a list of action result dicts.
    """
    log_finding(finding)

    actions = []

    if finding['severity_score'] < SEVERITY_THRESHOLD:
        logger.info(
            f"Severity {finding['severity_score']} is below threshold "
            f"{SEVERITY_THRESHOLD} — no automated action taken"
        )
        return actions

    bucket = finding.get('affected_bucket')
    key = finding.get('affected_object')

    if ENABLE_QUARANTINE and bucket and key:
        quarantine_result = quarantine_object(bucket, key, finding)
        actions.append(quarantine_result)

    if bucket and key:
        tag_result = tag_sensitive_object(bucket, key, finding)
        actions.append(tag_result)

    send_notification(finding, actions)

    return actions


def log_finding(finding):
    """Emit structured log lines for the finding."""
    logger.info("=" * 60)
    logger.info("MACIE FINDING DETECTED")
    logger.info("=" * 60)
    logger.info(f"Finding ID:    {finding.get('finding_id')}")
    logger.info(f"Type:          {finding.get('finding_type')}")
    logger.info(f"Severity:      {finding.get('severity_score')}")
    logger.info(f"Title:         {finding.get('title')}")
    logger.info(f"Region:        {finding.get('region')}")
    logger.info(f"Account:       {finding.get('account_id')}")
    logger.info(f"Bucket:        {finding.get('affected_bucket')}")
    logger.info(f"Object:        {finding.get('affected_object')}")
    logger.info(f"PII Types:     {json.dumps(finding.get('pii_types', []))}")
    logger.info("=" * 60)


def quarantine_object(bucket, key, finding):
    """
    Copy an object from the sensitive bucket to the quarantine bucket,
    tag the quarantine copy with finding metadata, then delete the original.

    Returns an action dict with status SUCCESS or FAILED.
    """
    quarantine_key = key  # preserve original key path in quarantine bucket

    try:
        # Copy to quarantine bucket
        s3_client.copy_object(
            CopySource={'Bucket': bucket, 'Key': key},
            Bucket=QUARANTINE_BUCKET,
            Key=quarantine_key,
            ServerSideEncryption='aws:kms',
            TaggingDirective='REPLACE',
            Tagging=(
                f"MacieFinding=true"
                f"&MacieSeverity={finding['severity_score']}"
                f"&FindingType={finding['finding_type']}"
                f"&QuarantinedAt={datetime.now(timezone.utc).isoformat()}"
                f"&FindingId={finding.get('finding_id', 'unknown')}"
            )
        )
        logger.info(f"Copied s3://{bucket}/{key} → s3://{QUARANTINE_BUCKET}/{quarantine_key}")

        # Delete original from sensitive bucket
        s3_client.delete_object(Bucket=bucket, Key=key)
        logger.info(f"Deleted original object s3://{bucket}/{key}")

        return {
            'action': 'QUARANTINE_OBJECT',
            'source_bucket': bucket,
            'source_key': key,
            'quarantine_bucket': QUARANTINE_BUCKET,
            'quarantine_key': quarantine_key,
            'status': 'SUCCESS',
        }

    except ClientError as e:
        logger.error(f"Error quarantining s3://{bucket}/{key}: {str(e)}")
        return {
            'action': 'QUARANTINE_OBJECT',
            'source_bucket': bucket,
            'source_key': key,
            'status': 'FAILED',
            'error': str(e),
        }


def tag_sensitive_object(bucket, key, finding):
    """
    Apply Macie finding tags to an S3 object so it can be identified later
    even if quarantine is disabled.

    Returns an action dict with status SUCCESS or FAILED.
    """
    try:
        s3_client.put_object_tagging(
            Bucket=bucket,
            Key=key,
            Tagging={
                'TagSet': [
                    {'Key': 'MacieFinding', 'Value': 'true'},
                    {'Key': 'MacieSeverity', 'Value': str(finding['severity_score'])},
                    {'Key': 'FindingType', 'Value': finding['finding_type']},
                    {'Key': 'QuarantinedAt', 'Value': datetime.now(timezone.utc).isoformat()},
                ]
            }
        )
        logger.info(f"Tagged s3://{bucket}/{key} with Macie finding metadata")

        return {
            'action': 'TAG_SENSITIVE_OBJECT',
            'bucket': bucket,
            'key': key,
            'status': 'SUCCESS',
        }

    except ClientError as e:
        logger.error(f"Error tagging s3://{bucket}/{key}: {str(e)}")
        return {
            'action': 'TAG_SENSITIVE_OBJECT',
            'bucket': bucket,
            'key': key,
            'status': 'FAILED',
            'error': str(e),
        }


def send_notification(finding, actions_taken):
    """
    Publish a formatted SNS alert for the finding.

    Exceptions are caught and logged — failure here must not prevent the
    rest of the handler from completing.
    """
    if not SNS_TOPIC_ARN:
        logger.info("SNS_TOPIC_ARN not configured, skipping notification")
        return

    try:
        actions_summary = "\n".join(
            f"  - {a.get('action', 'Unknown')}: {a.get('status', 'Unknown')}"
            for a in (actions_taken or [])
        ) or "  No automated actions taken"

        pii_summary = ", ".join(
            str(p.get('type', p)) for p in finding.get('pii_types', [])
        ) or "None detected"

        message = f"""
Macie Security Alert — {finding.get('environment', ENVIRONMENT).upper()}

Finding ID:    {finding.get('finding_id')}
Type:          {finding.get('finding_type')}
Severity:      {finding.get('severity_score')}/10
Title:         {finding.get('title')}
Region:        {finding.get('region')}
Account:       {finding.get('account_id')}

Affected Resource:
  Bucket: {finding.get('affected_bucket')}
  Object: {finding.get('affected_object')}

PII Types Detected:
  {pii_summary}

Automated Actions Taken:
{actions_summary}

Timestamp: {datetime.now(timezone.utc).isoformat()}
Environment: {ENVIRONMENT}
"""

        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[Macie Alert] {finding.get('finding_type')} — Severity {finding.get('severity_score')}",
            Message=message,
        )
        logger.info("SNS notification sent successfully")

    except Exception as e:
        logger.error(f"Error sending SNS notification: {str(e)}")


def create_response(status_code, message, actions=None):
    """Return a standardized Lambda response dict."""
    return {
        'statusCode': status_code,
        'body': json.dumps({
            'message': message,
            'actions': actions or [],
            'timestamp': datetime.now(timezone.utc).isoformat(),
        }),
    }
