# S3バケット名が一意になるようにランダム文字列を生成
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# 1. Route 53 ホストゾーンの参照（既存のホストゾーン情報を取得）
data "aws_route53_zone" "main" {
  provider     = aws.management
  name         = var.domain_name
  private_zone = false
}

# 2. ACM SSL/TLS 証明書の作成（us-east-1 で作成必須）
resource "aws_acm_certificate" "cert" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"] # サブドメインも一括対応
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# 3. ACM DNS 検証用レコードを Route 53 に自動作成
resource "aws_route53_record" "cert_validation" {
  provider = aws.management
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# 4. ACM 証明書の検証完了を待機
resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# 5. S3 バケット（Webホスティング用）
resource "aws_s3_bucket" "site" {
  bucket        = "okada-chikuro-site-${random_string.bucket_suffix.result}"
  force_destroy = true
}

# S3 パブリックアクセスブロック
resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 6. CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "s3-oac-${aws_s3_bucket.site.id}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 7. CloudFront ディストリビューション
resource "aws_cloudfront_distribution" "site" {
  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.site.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # 独自ドメイン（CAME / CNAME）の設定
  aliases = [var.domain_name, "www.${var.domain_name}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.site.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # ACM 証明書の紐付け
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# 8. S3 バケットポリシー
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
          }
        }
      }
    ]
  })
}

# 9. Route 53 DNS エイリアスレコード作成（ドメイン -> CloudFront）
resource "aws_route53_record" "root" {
  provider = aws.management
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = var.domain_name
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  provider = aws.management
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = "www.${var.domain_name}"
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

# ==================================================
# 10. SES (送信元・送信先メールアドレスの検証)
# ==================================================
resource "aws_ses_email_identity" "contact_email" {
  email = var.contact_email
}

# ==================================================
# 11. IAM Role & Policy (Lambda実行用ロール)
# ==================================================
resource "aws_iam_role" "lambda_exec_role" {
  name = "contact_form_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# CloudWatch Logs ログ出力権限
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SES メール送信権限（最小権限: 検証済みアイデンティティと送信元アドレスを限定）
resource "aws_iam_policy" "lambda_ses_policy" {
  name        = "contact_form_ses_policy"
  description = "Allow Lambda to send email via SES (scoped to the verified identity)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = aws_ses_email_identity.contact_email.arn
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.contact_email
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ses_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_ses_policy.arn
}

# ==================================================
# 12. Lambda 用 ZIP アーカイブの作成
# ==================================================
# ※プロジェクトルートからの相対パスで指定（環境に合わせて調整）
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../backend/src/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# ==================================================
# 13. Lambda 関数
# ==================================================
resource "aws_lambda_function" "contact_form" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "contact-form-handler"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      SENDER_EMAIL    = var.contact_email
      RECIPIENT_EMAIL = var.contact_email
      ALLOWED_ORIGINS = join(",", var.allowed_origins)
    }
  }
}

# ==================================================
# 14. API Gateway (HTTP API) & CORS
# ==================================================
resource "aws_apigatewayv2_api" "http_api" {
  name          = "contact-form-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type"]
    allow_methods = ["POST", "OPTIONS"]
    allow_origins = var.allowed_origins
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.contact_form.invoke_arn
}

resource "aws_apigatewayv2_route" "post_contact" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# API Gateway から Lambda を呼び出す許可
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact_form.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# ==================================================
# 15. Outputs (完成した API エンドポイントを表示)
# ==================================================
output "api_endpoint" {
  value       = "${aws_apigatewayv2_stage.default.invoke_url}contact"
  description = "Contact Form API Endpoint URL"
}