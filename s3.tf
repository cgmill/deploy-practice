resource "aws_s3_bucket" "artifact_store" {
  bucket = "artifact-store-${local.account_id}-${local.aws_region}"
}

resource "aws_s3_bucket_public_access_block" "artifact_store_block" {
  bucket = aws_s3_bucket.artifact_store.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
