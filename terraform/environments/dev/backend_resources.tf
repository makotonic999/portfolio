# Devアカウント用のステート保存S3バケット
resource "aws_s3_bucket" "tf_state" {
  bucket = "okadachikuro-dev-tfstate"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_enc" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# tfstate バケットのパブリックアクセスを全面的にブロックする。
# ステートファイルには機微情報が含まれ得るため、公開経路を一切作らない。
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ステートの排他制御（ロック）用 DynamoDB テーブル
resource "aws_dynamodb_table" "tf_locks" {
  name         = "terraform-locks-dev"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

resource "aws_ecr_repository" "backend" {
  name = "corporate-site-backend"
  # タグの上書きを禁止し、イメージの改ざん（タグ付け替えによる差し替え）を防ぐ。
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}