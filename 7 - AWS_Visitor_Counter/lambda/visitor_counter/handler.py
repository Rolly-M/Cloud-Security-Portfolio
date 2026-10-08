import json
import os
import hashlib
import re
import time

import boto3
from botocore.exceptions import ClientError

TABLE_NAME  = os.environ['TABLE_NAME']
TTL_SECONDS = int(os.environ.get('VISITOR_TTL_SECONDS', '86400'))

ddb   = boto3.resource('dynamodb')
table = ddb.Table(TABLE_NAME)

# Accepts UUIDs and any alphanumeric/hyphen/underscore string 8–64 chars.
_VID_RE = re.compile(r'^[a-zA-Z0-9_\-]{8,64}$')


def handler(event, context):
    # Prefer the client-supplied visitor_id (localStorage UUID) so that
    # each browser is counted once regardless of IP changes.  Fall back to
    # a hashed source IP for clients where localStorage is unavailable.
    body = {}
    if event.get('body'):
        try:
            body = json.loads(event['body'])
        except Exception:
            pass

    client_id = str(body.get('visitor_id', '')).strip()
    if client_id and _VID_RE.match(client_id):
        visitor_key = 'vc#' + hashlib.sha256(client_id.encode()).hexdigest()[:32]
    else:
        ip = (event.get('requestContext', {})
                   .get('http', {})
                   .get('sourceIp', 'unknown'))
        visitor_key = 'vi#' + hashlib.sha256(ip.encode()).hexdigest()[:16]

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
