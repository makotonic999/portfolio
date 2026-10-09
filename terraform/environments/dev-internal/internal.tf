# ==================================================
# 社内（客先提示）用ポートフォリオ
#   profile.okada-chikuro-kougyousyo.com
#
# 【state 分離方針】
#   本体（environments/dev）とは独立した state（dev/profile.tfstate）で管理する。
#   本体が「所有」する共有インフラ（ACM ワイルドカード証明書 / Route 53 ホスト
#   ゾーン）は data source で「参照のみ」行い、二重管理・相互 destroy を避ける。
# ==================================================

locals {
  internal_subdomain = "profile.${var.domain_name}"
}

# --- 共有インフラの参照（所有は本体 environments/dev 側） ---

# ワイルドカード証明書（*.<domain> を含む）。us-east-1 で本体が発行・管理。
data "aws_acm_certificate" "wildcard" {
  provider    = aws.us_east_1
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# ルートドメインのホストゾーン（管理アカウント側）。
data "aws_route53_zone" "main" {
  provider     = aws.management
  name         = var.domain_name
  private_zone = false
}

# --- 社内サイト本体（この state が所有する 6 リソース） ---

# 1. S3 バケット（社内用 Web ホスティング）
#    バケット名は既存リソースに一致させる（分離は import により既存を取り込む）。
resource "aws_s3_bucket" "site_internal" {
  bucket        = "okada-chikuro-site-internal-hmd17889"
  force_destroy = true
}

# S3 パブリックアクセスブロック
resource "aws_s3_bucket_public_access_block" "site_internal" {
  bucket                  = aws_s3_bucket.site_internal.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "oac_internal" {
  name                              = "s3-oac-${aws_s3_bucket.site_internal.id}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 3. CloudFront ディストリビューション
resource "aws_cloudfront_distribution" "site_internal" {
  origin {
    domain_name              = aws_s3_bucket.site_internal.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.site_internal.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac_internal.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [local.internal_subdomain]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.site_internal.id}"

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

  # 本体のワイルドカード証明書を参照（*.<domain> を含む）
  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.wildcard.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# 4. S3 バケットポリシー（CloudFront OAC からのみ許可）
resource "aws_s3_bucket_policy" "site_internal" {
  bucket = aws_s3_bucket.site_internal.id
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
        Resource = "${aws_s3_bucket.site_internal.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site_internal.arn
          }
        }
      }
    ]
  })
}

# 5. Route 53 DNS エイリアスレコード（profile.<domain> -> CloudFront）
resource "aws_route53_record" "internal" {
  provider = aws.management
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = local.internal_subdomain
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.site_internal.domain_name
    zone_id                = aws_cloudfront_distribution.site_internal.hosted_zone_id
    evaluate_target_health = false
  }
}

# ==================================================
# Outputs（社内用）
# ==================================================
output "s3_bucket_name_internal" {
  value       = aws_s3_bucket.site_internal.id
  description = "社内（客先）用サイトのS3バケット名"
}

output "cloudfront_distribution_id_internal" {
  value       = aws_cloudfront_distribution.site_internal.id
  description = "社内（客先）用サイトのCloudFrontディストリビューションID"
}

output "custom_domain_url_internal" {
  value       = "https://${local.internal_subdomain}"
  description = "社内（客先）用サイトのURL"
}
