import json
import os
import hashlib
import re
import time

import boto3
from decimal import Decimal

TABLE_NAME = os.environ['TABLE_NAME']
ACT_TTL    = int(os.environ.get('ACTIVITY_TTL_SECONDS', str(30 * 86400)))

ddb   = boto3.resource('dynamodb')
table = ddb.Table(TABLE_NAME)

_VID_RE  = re.compile(r'^[a-zA-Z0-9_\-]{8,64}$')
_PAGE_RE = re.compile(r'^[/a-zA-Z0-9\-_.]{0,100}$')


def handler(event, context):
    body = {}
    if event.get('body'):
        try:
            body = json.loads(event['body'])
        except Exception:
            pass

    ev_type = str(body.get('type', '')).strip()

    client_id = str(body.get('visitor_id', '')).strip()
    vid_hash  = (hashlib.sha256(client_id.encode()).hexdigest()[:16]
                 if (client_id and _VID_RE.match(client_id)) else 'unknown')

    expires_at = int(time.time()) + ACT_TTL

    if ev_type == 'duration':
        # Accumulate session duration in the shared totals row.
        # Accept 3 s – 60 min; reject sub-second noise and extreme outliers.
        dur = body.get('duration_ms')
        if isinstance(dur, (int, float)) and 3000 <= dur <= 3_600_000:
            table.update_item(
                Key={'pk': 'totals'},
                UpdateExpression='ADD total_duration_ms :dur, duration_count :one',
                ExpressionAttributeValues={
                    ':dur': Decimal(str(int(dur))),
                    ':one': Decimal('1'),
                },
            )

    elif ev_type == 'click':
        page    = str(body.get('page',    '')).strip()[:80]
        element = str(body.get('element', '')).strip()[:80]
        href    = str(body.get('href',    '')).strip()[:200]

        if not page or not _PAGE_RE.match(page):
            page = '/'

        ts = int(time.time() * 1000)
        table.put_item(Item={
            'pk':         f'act#{vid_hash}#{ts}',
            'event_type': 'click',
            'page':       page,
            'element':    element,
            'href':       href,
            'expires_at': expires_at,
        })

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'ok': True}),
    }
