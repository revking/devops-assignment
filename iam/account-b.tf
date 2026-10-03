###############################################################################
# Account B - roleC and the one bucket it may use
###############################################################################

resource "aws_s3_bucket" "roleC" {
  provider = aws.account_b
  bucket   = var.roleC_bucket_name
}

resource "aws_s3_bucket_public_access_block" "roleC" {
  provider                = aws.account_b
  bucket                  = aws_s3_bucket.roleC.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "roleC" {
  provider = aws.account_b
  bucket   = aws_s3_bucket.roleC.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "roleC" {
  provider             = aws.account_b
  name                 = "roleC"
  description          = "Full access to ${var.roleC_bucket_name}; assumable only by Account A roleB"
  max_session_duration = 3600

  # Trust roleB's exact ARN, not arn:aws:iam::<A>:root (see NOTES.md, Task 3).
  # Referencing the resource also makes Terraform create roleB first; IAM rejects
  # a trust policy whose principal does not exist.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OnlyRoleBFromAccountA"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.roleB.arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "roleC_s3" {
  provider = aws.account_b
  name     = "roleC-s3-access"
  role     = aws_iam_role.roleC.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "FullAccessToOneBucket"
      Effect = "Allow"
      Action = "s3:*"
      Resource = [
        aws_s3_bucket.roleC.arn,        # bucket-level actions (ListBucket, GetBucketPolicy, ...)
        "${aws_s3_bucket.roleC.arn}/*", # object-level actions (GetObject, PutObject, ...)
      ]
    }]
  })
}
