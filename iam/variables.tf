variable "region" {
  description = "Region used for the providers and for regional ARNs (ECR, ECS)."
  type        = string
  default     = "us-east-1"
}

variable "account_a_id" {
  description = "Account A ID."
  type        = string
  default     = "000000000000"
}

variable "account_b_id" {
  description = "Account B ID."
  type        = string
  default     = "111111111111"
}

variable "account_a_profile" {
  description = "AWS CLI profile with IAM admin rights in Account A."
  type        = string
  default     = "account-a"
}

variable "account_b_profile" {
  description = "AWS CLI profile with IAM admin rights in Account B."
  type        = string
  default     = "account-b"
}

variable "group1_users" {
  description = "Programmatic-only users (group1). Must include engine and ci."
  type        = set(string)
  default     = ["engine", "ci"]

  validation {
    condition     = contains(var.group1_users, "engine") && contains(var.group1_users, "ci")
    error_message = "group1 must contain the engine and ci users."
  }
}

variable "group2_users" {
  description = "Console + CLI users (group2)."
  type        = set(string)
  default     = ["alice", "bob"]
}

variable "pgp_key" {
  description = <<-EOT
    Base64 PGP public key (or keybase:username) used to encrypt initial console
    passwords and access-key secrets. When null, Terraform creates no passwords or
    access keys, so no plaintext secret can ever land in state.
  EOT
  type        = string
  default     = null
}

variable "roleC_bucket_name" {
  description = "The single S3 bucket in Account B that roleC gets full access to."
  type        = string
  default     = "acme-account-b-shared-data"
}

# ---- Task 4 (ci user) targets ----

variable "ci_ecr_repository_name" {
  description = "ECR repository the CI pipeline pushes to."
  type        = string
  default     = "app"
}

variable "ci_ecs_cluster_name" {
  description = "ECS cluster hosting the service CI deploys."
  type        = string
  default     = "app-cluster"
}

variable "ci_ecs_service_name" {
  description = "ECS service CI deploys new task definitions to."
  type        = string
  default     = "app-service"
}

variable "ci_ecs_task_role_names" {
  description = "Roles referenced by the task definition (execution role + task role) that CI must be allowed to pass to ECS."
  type        = list(string)
  default     = ["app-task-execution-role", "app-task-role"]
}

variable "ci_artifacts_bucket_name" {
  description = "S3 bucket holding build artifacts that CI reads."
  type        = string
  default     = "acme-build-artifacts"
}
