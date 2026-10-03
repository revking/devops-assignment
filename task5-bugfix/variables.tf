variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "account_a_id" {
  description = "Account that owns roleB."
  type        = string
  default     = "000000000000"
}

variable "account_b_id" {
  description = "Account that owns roleC (where this runs)."
  type        = string
  default     = "111111111111"
}

variable "bucket_name" {
  description = "The one S3 bucket roleC may access."
  type        = string
  default     = "acme-account-b-shared-data"
}
