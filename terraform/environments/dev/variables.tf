# variables.tf

variable "domain_name" {
  type        = string
  description = "サイトのルートドメイン名"
  default     = "okada-chikuro-kougyousyo.com"
}

# お問い合わせフォームの送信元・通知先メールアドレス
# （SES で検証済みのアドレスを指定する）
variable "contact_email" {
  type        = string
  description = "お問い合わせフォームの送信元／通知先メールアドレス（SES検証済み）"
  default     = "makotonic999@gmail.com"
}

# CORS を許可するオリジン（本番ドメインのみを許可し、ワイルドカードを避ける）
variable "allowed_origins" {
  type        = list(string)
  description = "お問い合わせAPI（API Gateway / Lambda）で許可する CORS オリジンの一覧"
  default = [
    "https://okada-chikuro-kougyousyo.com",
    "https://www.okada-chikuro-kougyousyo.com",
  ]
}

# GitHub Actions OIDC 用: 対象リポジトリ（owner/repo 形式）
variable "github_repository" {
  type        = string
  description = "OIDC でロールを引き受けられる GitHub リポジトリ（owner/repo）"
  default     = "makotonic999/portfolio"
}

# OIDC でロールを引き受けられる ref（ブランチ）の一覧。
# sub は "repo:<owner>/<repo>:ref:<ref>" まで限定する。
variable "github_deploy_refs" {
  type        = list(string)
  description = "デプロイを許可する Git ref（例: refs/heads/main）"
  default = [
    "refs/heads/main",
  ]
}
