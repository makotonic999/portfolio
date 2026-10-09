# 1. GitHub OIDCプロバイダーの定義
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

# 2. バックエンド用 IAM ロール
resource "aws_iam_role" "github_actions_backend_deploy" {
  name = "GitHubActionsBackendDeployRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          # OIDC の sub はリポジトリ＋ブランチ(ref)まで厳格に限定する。
          # 広いワイルドカード（repo:owner*repo*:*）は他リポジトリやPRから
          # ロールを引き受けられる余地を残すため避ける。
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              for ref in var.github_deploy_refs : "repo:${var.github_repository}:ref:${ref}"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "backend_deploy_policy" {
  name = "BackendDeployPolicy"
  role = aws_iam_role.github_actions_backend_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "*"
      }
    ]
  })
}

output "github_actions_backend_role_arn" {
  value = aws_iam_role.github_actions_backend_deploy.arn
}

# ==========================================
# 2. フロントエンド用 IAM ロール
# ==========================================
resource "aws_iam_role" "github_actions_deploy" {
  name = "GitHubActionsFrontendDeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          # sub はリポジトリ＋ブランチ(ref)まで限定（最小権限）
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              for ref in var.github_deploy_refs : "repo:${var.github_repository}:ref:${ref}"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "deploy_policy" {
  name = "FrontendDeployPolicy"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation"
        ]
        Resource = aws_cloudfront_distribution.site.arn
      }
    ]
  })
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_deploy.arn
  description = "IAM Role ARN for GitHub Actions OIDC"
}