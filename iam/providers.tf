# One configuration, two accounts. Each provider is pinned to its account with
# allowed_account_ids so a mis-set profile fails fast instead of writing IAM into
# the wrong account.

provider "aws" {
  alias               = "account_a"
  region              = var.region
  profile             = var.account_a_profile
  allowed_account_ids = [var.account_a_id]

  default_tags {
    tags = { ManagedBy = "terraform", Stack = "iam-multi-account" }
  }
}

provider "aws" {
  alias               = "account_b"
  region              = var.region
  profile             = var.account_b_profile
  allowed_account_ids = [var.account_b_id]

  default_tags {
    tags = { ManagedBy = "terraform", Stack = "iam-multi-account" }
  }
}
