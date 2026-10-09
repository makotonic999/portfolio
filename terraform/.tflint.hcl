// TFLint 設定
// - terraform ルールセット: 公式のベストプラクティス（命名・非推奨構文など）
// - aws ルールセット: AWS 固有の設定ミス検出
//
// 導入フェーズ1では CI 側で soft-fail（可視化のみ）とし、
// ここでは検出ルールを有効化して「何が指摘されるか」を見える化する。

config {
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.37.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
