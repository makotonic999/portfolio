import json
import os
import boto3
from botocore.exceptions import ClientError

ses_client = boto3.client('ses', region_name='ap-northeast-1')

# SESで検証済みのメールアドレスを環境変数から取得（後ほど設定）
SENDER_EMAIL = os.environ.get('SENDER_EMAIL')
RECIPIENT_EMAIL = os.environ.get('RECIPIENT_EMAIL')

# CORS許可オリジン（カンマ区切りの環境変数 ALLOWED_ORIGINS で指定）
# 例: "https://okada-chikuro-kougyousyo.com,https://www.okada-chikuro-kougyousyo.com"
ALLOWED_ORIGINS = [
    o.strip()
    for o in os.environ.get('ALLOWED_ORIGINS', '').split(',')
    if o.strip()
]


def _resolve_origin(event):
    """リクエストの Origin が許可リストに含まれる場合のみ、その Origin を返す。

    許可されない（または Origin 未指定の）場合は許可リストの先頭を返し、
    ワイルドカード ``*`` でのレスポンスを避ける。
    """
    headers = event.get('headers') or {}
    # API Gateway はヘッダー名を小文字化して渡すため両方を参照する
    request_origin = headers.get('origin') or headers.get('Origin')
    if request_origin and request_origin in ALLOWED_ORIGINS:
        return request_origin
    return ALLOWED_ORIGINS[0] if ALLOWED_ORIGINS else ''


def _cors_headers(origin):
    headers = {
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'OPTIONS,POST',
        'Vary': 'Origin',
    }
    if origin:
        headers['Access-Control-Allow-Origin'] = origin
    return headers


def lambda_handler(event, context):
    origin = _resolve_origin(event)
    cors = _cors_headers(origin)
    try:
        # 1. API Gateway / フロントエンドからのリクエストデータを解析
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', {})

        name = body.get('name', '未入力')
        email = body.get('email', '未入力')
        message = body.get('message', '未入力')

        # 送信元サイトの識別（未指定の場合は従来挙動を維持）
        source = body.get('source')
        SOURCE_LABELS = {
            'profile': '社内ポートフォリオ',
        }
        source_label = SOURCE_LABELS.get(source)

        # 2. メールの件名と本文を構築
        # source_label がある場合のみ件名・本文に送信元を明記（後方互換）
        if source_label:
            subject = f"【{source_label}】{name} 様よりお問い合わせ"
            source_line = f"■ 送信元サイト:\n{source_label}\n\n"
        else:
            subject = f"【Webサイトお問い合わせ】{name} 様より"
            source_line = ""

        body_text = f"""
Webサイトからお問い合わせがありました。

{source_line}■ お名前:
{name}

■ メールアドレス:
{email}

■ お問い合わせ内容:
{message}
"""

        # 3. SESを使用してメール送信
        response = ses_client.send_email(
            Source=SENDER_EMAIL,
            Destination={'ToAddresses': [RECIPIENT_EMAIL]},
            Message={
                'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                'Body': {'Text': {'Data': body_text, 'Charset': 'UTF-8'}}
            },
            ReplyToAddresses=[email]  # 返信先を入力されたアドレスに設定
        )

        # 4. 成功レスポンス（CORSヘッダー含む）
        return {
            'statusCode': 200,
            'headers': {**cors, 'Content-Type': 'application/json'},
            'body': json.dumps({'message': 'Email sent successfully!'})
        }

    except ClientError as e:
        print(f"SES Error: {e.response['Error']['Message']}")
        return {
            'statusCode': 500,
            'headers': {**cors, 'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Failed to send email.'})
        }
    except Exception as e:
        print(f"Unexpected Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {**cors, 'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error.'})
        }