import json
import os
import boto3
from botocore.exceptions import ClientError

ses_client = boto3.client('ses', region_name='ap-northeast-1')

# SESで検証済みのメールアドレスを環境変数から取得（後ほど設定）
SENDER_EMAIL = os.environ.get('SENDER_EMAIL')
RECIPIENT_EMAIL = os.environ.get('RECIPIENT_EMAIL')

def lambda_handler(event, context):
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
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,POST'
            },
            'body': json.dumps({'message': 'Email sent successfully!'})
        }

    except ClientError as e:
        print(f"SES Error: {e.response['Error']['Message']}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Failed to send email.'})
        }
    except Exception as e:
        print(f"Unexpected Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Internal server error.'})
        }