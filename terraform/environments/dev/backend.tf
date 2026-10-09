terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # S3 バケット名のサフィックス生成に使用（main.tf: random_string）
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    # Lambda の ZIP アーカイブ生成に使用（main.tf: data.archive_file）
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # ステートの保存先をS3に設定（※バックエンド作成後にコメントアウトを外します）
  backend "s3" {
    bucket       = "okadachikuro-dev-tfstate"
    key          = "dev/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    profile      = "dev"
  }
}