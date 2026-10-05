# ==================================================
# 社内（客先提示）用ポートフォリオ
#   profile.okada-chikuro-kougyousyo.com
#
# 本体（main.tf）には一切手を加えず、別ファイルで追加する。
# ACM 証明書は main.tf の *.${var.domain_name} ワイルドカード証明書
# （aws_acm_certificate_validation.cert）をそのまま流用する。
# ==================================================

# サブドメイン名（profile.<domain>）
locals {
  internal_subdomain = "profile.${var.domain_name}"
}

# 1. S3 バケット（社内用 Web ホスティング）
resource "aws_s3_bucket" "site_internal" {
  bucket        = "okada-chikuro-site-internal-${random_string.bucket_suffix.result}"
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

  # 独自サブドメイン
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

  # ACM 証明書は本体のワイルドカード証明書を流用（*.<domain> を含む）
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
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
