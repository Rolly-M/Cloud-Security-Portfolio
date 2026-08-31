import json
import os
import hashlib
import time

import boto3
from botocore.exceptions import ClientError

TABLE_NAME  = os.environ['TABLE_NAME']
TTL_SECONDS = int(os.environ.get('VISITOR_TTL_SECONDS', '86400'))

ddb   = boto3.resource('dynamodb')
table = ddb.Table(TABLE_NAME)


def handler(event, context):
    # Derive a privacy-preserving visitor token from the source IP.
    # The hash is truncated to 16 hex chars — collision risk is negligible
    # at portfolio-level traffic and we never store raw IPs.
    ip = (event.get('requestContext', {})
               .get('http', {})
               .get('sourceIp', 'unknown'))
    visitor_key = 'visitor#' + hashlib.sha256(ip.encode()).hexdigest()[:16]
    expires_at  = int(time.time()) + TTL_SECONDS

    is_new_visitor = False

    # Conditional write: succeeds only when the item doesn't exist yet.
    # This is the atomic uniqueness check — no read-modify-write race.
    try:
        table.put_item(
            Item={'pk': visitor_key, 'expires_at': expires_at},
            ConditionExpression='attribute_not_exists(pk)',
        )
        is_new_visitor = True
    except ClientError as exc:
        if exc.response['Error']['Code'] != 'ConditionalCheckFailedException':
            raise

    # Atomically increment totals row.
    update_expr    = 'ADD total_visits :one'
    expr_values    = {':one': 1}
    if is_new_visitor:
        update_expr += ', unique_visitors :one'

    table.update_item(
        Key={'pk': 'totals'},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=expr_values,
    )

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'ok': True, 'new_visitor': is_new_visitor}),
    }
