variable "region" {
  description = "Region for the state bucket and lock table."
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "Account that owns the state backend."
  type        = string
  default     = "000000000000"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string
  default     = "acme-tfstate-000000000000-us-east-1"
}

variable "lock_table_name" {
  description = "DynamoDB table used for Terraform state locking."
  type        = string
  default     = "terraform-state-locks"
}

variable "noncurrent_version_retention_days" {
  description = "How long old state versions are kept for recovery."
  type        = number
  default     = 90
}
