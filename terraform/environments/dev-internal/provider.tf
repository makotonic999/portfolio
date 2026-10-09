provider "aws" {
  region  = "ap-northeast-1"
  profile = "dev"
}

# CloudFront 用 ACM 証明書は us-east-1 で管理されているため参照用に追加
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "dev"
}

# Route 53（ホストゾーン）は管理アカウント側にあるためクロスアカウント参照用
provider "aws" {
  alias   = "management"
  region  = "ap-northeast-1"
  profile = "dev"

  assume_role {
    role_arn     = "arn:aws:iam::761018859875:role/TerraformRoute53CrossAccountRole"
    session_name = "TerraformRoute53InternalSession"
  }
}
