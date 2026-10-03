variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS account this stack is allowed to run against (guards against wrong-account applies)."
  type        = string
  default     = "000000000000"
}

variable "environment" {
  description = "Environment tag value."
  type        = string
}

variable "owner" {
  description = "Owner tag value."
  type        = string
}

variable "instances" {
  description = "Instance specs passed straight to the ec2-fleet module. See modules/ec2-fleet/variables.tf for the schema."
  type        = any
}
