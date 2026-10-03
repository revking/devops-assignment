output "state_bucket" {
  description = "Name of the Terraform state bucket."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Name of the DynamoDB lock table."
  value       = aws_dynamodb_table.locks.name
}

output "kms_key_arn" {
  description = "KMS key encrypting state objects."
  value       = aws_kms_key.state.arn
}
