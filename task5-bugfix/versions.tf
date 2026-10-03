terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# roleC lives in Account B, so this configuration must run with Account B
# credentials. allowed_account_ids makes a wrong-account run fail immediately.
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_b_id]
}
