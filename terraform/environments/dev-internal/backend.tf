terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 社内（profile）案件専用のステート。
  # 本体（environments/dev）とは state キーを分離し、相互の apply で
  # 片方のリソースが destroy されないようにする。
  backend "s3" {
    bucket       = "okadachikuro-dev-tfstate"
    key          = "dev/profile.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    profile      = "dev"
  }
}
