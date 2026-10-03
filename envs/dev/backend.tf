# Task 2 - remote state in S3 with DynamoDB state locking.
#
# The bucket and table are created by bootstrap/state-backend (run that once, with
# local state, before `terraform init` here). Backend blocks cannot use variables,
# so these values are literals; override per environment with
# `terraform init -backend-config=...` if needed.
terraform {
  backend "s3" {
    bucket         = "acme-tfstate-000000000000-us-east-1"
    key            = "ec2-fleet/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"

    # Terraform >= 1.10 can also lock with an S3 lock file (use_lockfile = true),
    # and HashiCorp has deprecated dynamodb_table in favour of it. The assignment
    # asks for DynamoDB, so that is what is configured; see NOTES.md (Task 2).
  }
}
