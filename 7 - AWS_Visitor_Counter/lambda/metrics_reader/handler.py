import json
import os
from datetime import datetime, timezone, timedelta

import boto3

TABLE_NAME   = os.environ['TABLE_NAME']
COUNTER_FN   = os.environ['COUNTER_FUNCTION_NAME']
# AWS_REGION is injected automatically by the Lambda runtime
AWS_REGION   = os.environ.get('AWS_REGION', 'ca-central-1')

ddb   = boto3.resource('dynamodb')
cw    = boto3.client('cloudwatch', region_name=AWS_REGION)
table = ddb.Table(TABLE_NAME)


def _cw_stat(metric, stat, start, end, period):
    r = cw.get_metric_statistics(
        Namespace='AWS/Lambda',
        MetricName=metric,
        Dimensions=[{'Name': 'FunctionName', 'Value': COUNTER_FN}],
        StartTime=start,
        EndTime=end,
        Period=period,
        Statistics=[stat],
    )
    pts = r.get('Datapoints', [])
    return pts[0][stat] if pts else 0


def handler(event, context):
    end   = datetime.now(timezone.utc)
    start = end - timedelta(hours=24)

    # ── DynamoDB totals ───────────────────────────────────────────
    row    = table.get_item(Key={'pk': 'totals'}).get('Item', {})
    total  = int(row.get('total_visits',    0))
    unique = int(row.get('unique_visitors', 0))

    # ── CloudWatch: 24-hour aggregates ───────────────────────────
    req24   = int(_cw_stat('Invocations', 'Sum',     start, end, 86400))
    errors  = int(_cw_stat('Errors',      'Sum',     start, end, 86400))
    latency = round(_cw_stat('Duration',  'Average', start, end, 86400), 1)
    success = round((1 - errors / max(req24, 1)) * 100, 1)

    # ── Hourly breakdown: 24 one-hour buckets ─────────────────────
    r = cw.get_metric_statistics(
        Namespace='AWS/Lambda',
        MetricName='Invocations',
        Dimensions=[{'Name': 'FunctionName', 'Value': COUNTER_FN}],
        StartTime=start,
        EndTime=end,
        Period=3600,
        Statistics=['Sum'],
    )
    # Map each datapoint to its bucket index (0 = oldest hour)
    hourly_map = {
        int((p['Timestamp'].replace(tzinfo=timezone.utc) - start).total_seconds() // 3600): int(p['Sum'])
        for p in r.get('Datapoints', [])
    }
    hourly = [hourly_map.get(i, 0) for i in range(24)]

    body = {
        'total_visits':    total,
        'unique_visitors': unique,
        'requests_24h':    req24,
        'avg_latency_ms':  latency,
        'success_rate':    success,
        'errors_24h':      errors,
        'hourly_requests': hourly,
        'updated_at':      end.isoformat(),
    }

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            # CORS is enforced at the API Gateway layer; this header is a belt-and-suspenders.
            'Access-Control-Allow-Origin': '*',
        },
        'body': json.dumps(body),
    }
