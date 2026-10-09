# ==================================================
# SNS トピック（アラーム通知先）
# ==================================================
resource "aws_sns_topic" "alerts" {
  name = "cloudwatch-alerts-dev"

  # 保管時の暗号化（AWS マネージドキー）。トピックに流れる通知内容を保護する。
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "makotonic999@gmail.com"
}

# ==================================================
# Lambda エラーアラーム
# ==================================================
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name  = "lambda-contact-form-errors"
  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.contact_form.function_name
  }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_description   = "Lambda contact-form-handler でエラーが発生しました"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# ==================================================
# API Gateway 5xx エラーアラーム
# ==================================================
resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  alarm_name  = "apigw-contact-form-5xx"
  namespace   = "AWS/ApiGateway"
  metric_name = "5XXError"
  dimensions = {
    ApiId = aws_apigatewayv2_api.http_api.id
  }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_description   = "API Gateway で5xxエラーが発生しました"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}
