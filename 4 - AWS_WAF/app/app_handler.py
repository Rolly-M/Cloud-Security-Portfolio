"""
AWS WAF Demo — Protected Web Application Handler

This Lambda function serves as the backend web application that sits behind
the WAFv2 WebACL. It demonstrates a simple HTTP API protected by WAF rules
including SQLi, XSS, Known Bad Inputs, and rate limiting.

Author: Cloud Security Portfolio
Version: 1.0.0
"""

import json
import logging
import os
from datetime import datetime, timezone

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
PROJECT = os.environ.get('PROJECT', 'waf-security')


def lambda_handler(event, context):
    """
    Main Lambda handler for the WAF-protected web application.

    Requests that reach this function have already passed WAF inspection.
    Malicious requests (SQLi, XSS, known bad inputs, rate-limited IPs) are
    blocked by WAF before they ever invoke this function.
    """
    logger.info(json.dumps({"event_summary": {
        "path": event.get('rawPath', '/'),
        "method": event.get('requestContext', {}).get('http', {}).get('method', 'GET'),
        "source_ip": event.get('requestContext', {}).get('http', {}).get('sourceIp', 'unknown'),
    }}))

    method = event.get('requestContext', {}).get('http', {}).get('method', 'GET')
    path = event.get('rawPath', '/')
    query = event.get('queryStringParameters') or {}
    body_raw = event.get('body', '')

    return create_response(200, {
        'message': 'Request processed successfully',
        'method': method,
        'path': path,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'waf_protected': True,
    })


def create_response(status_code, body):
    """Create a standardised API Gateway HTTP API response."""
    return {
        'statusCode': status_code,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(body),
    }
