terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Deliberately local state: this stack creates the S3 bucket and DynamoDB table
  # that every other stack uses as its backend, so it cannot store its own state
  # there until they exist. After the first apply it can be migrated with
  # `terraform init -migrate-state` once a backend block is added.
}
