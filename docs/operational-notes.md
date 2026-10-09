# 運用上の注意（Operational Notes）

インフラの設定変更に伴い、デプロイ・運用時に注意すべき点を記録する。

---

## ECR のタグが IMMUTABLE 化されている（backend デプロイ時の注意）

### 背景
IaC のセキュリティ強化（AVD-AWS-0031）に伴い、ECR リポジトリ
`corporate-site-backend` の `image_tag_mutability` を **`IMMUTABLE`** に変更した。

- 定義: `terraform/environments/dev/backend_resources.tf`
- 目的: 同一タグでのイメージ上書きを禁止し、タグ付け替えによるイメージ改ざんを防ぐ。

### 問題
現在の `.github/workflows/backend-ci.yml` は、イメージに
**コミットSHA (`${{ github.sha }}`) と `latest` の2つのタグ**を付け、
`docker push --all-tags` で push している。

```yaml
IMAGE_TAG: ${{ github.sha }}
run: |
  docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG -t $ECR_REGISTRY/$ECR_REPOSITORY:latest .
  docker push $ECR_REGISTRY/$ECR_REPOSITORY --all-tags
```

- コミットSHAタグは毎回ユニークなので IMMUTABLE と両立し、問題ない。
- **`latest` タグは2回目以降の push で失敗する**（IMMUTABLE では既存タグの上書き不可）。
  - エラー例: `tag invalid: ... cannot be overwritten because the repository is immutable`
  - 初回 push は成功するが、以降のデプロイが落ちる。

### 対処（いずれか）
1. **`latest` タグ付与をやめる**（推奨）
   - CI では コミットSHA タグのみを push する。
   - Lambda/ECS 等の参照側は「最新の SHA タグ」を解決して使う運用にする。

   ```yaml
   # 例: latest を外し、SHA タグのみ push
   run: |
     docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
     docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
   ```

2. **可変タグ運用を続けたい場合は ECR を MUTABLE に戻す**
   - その場合は AVD-AWS-0031 を許容する判断となるため、
     `terraform/.trivyignore` に理由付きで追記し、意図を明示すること。
   - セキュリティ上は 1 の対処（SHA タグ運用）を推奨。

### 補足
backend（Go）はコンテナ移行の技術検証用で、本番のお問い合わせ処理は
Python Lambda（`backend/src/lambda_function.py`）が担っている。
そのため本問題が本番のお問い合わせ機能に即時影響するわけではないが、
backend をデプロイする際には上記を解消しておくこと。
