provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Stack     = "ec2-fleet"
    }
  }
}
