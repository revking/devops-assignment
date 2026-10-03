# DevOps Assignment: Terraform and AWS IAM

This repo contains Terraform for five tasks: a multi-instance EC2 module, S3/DynamoDB remote state, multi-account IAM with cross-account access, a least-privilege CI policy, and a bug fix.
The written answers and design rationale are in **[NOTES.md](NOTES.md)**.

## Repository layout

```
.
├── modules/ec2-fleet/          # Task 1: reusable module, 1 variable -> N instances
├── envs/dev/                   # Task 1 + 2: root stack; the 5 instances in terraform.tfvars
│   └── backend.tf              #   Task 2: S3 backend + DynamoDB locking
├── bootstrap/state-backend/    # Task 2: creates the state bucket + lock table (local state)
├── iam/                        # Task 3 + 4: Account A and Account B in one config
│   ├── account-a.tf            #   group1, group2, users, roleA, roleB
│   ├── account-b.tf            #   roleC + its bucket
│   ├── ci-policy.tf            #   Task 4: least-privilege policy attached to `ci`
│   └── policies/               #   Task 4: policy JSON + the template Terraform uses
├── task5-bugfix/               # Task 5: original snippet (.txt) and fixed main.tf
├── NOTES.md                    # All explanations and answers
└── README.md
```

## How to deploy (real accounts)

1. Replace the placeholder account IDs, bucket names and profiles in `*.tfvars` / `variables.tf` / `backend.tf`.
2. Bootstrap state (once, in Account A):
   ```bash
   cd bootstrap/state-backend && terraform init && terraform apply
   ```
3. EC2 fleet:
   ```bash
   cd envs/dev && terraform init && terraform plan -out tfplan && terraform apply tfplan
   ```
4. IAM. You need CLI profiles `account-a` and `account-b` with IAM admin rights. Optionally pass `-var pgp_key=keybase:<you>` to create PGP-encrypted passwords and keys.
   ```bash
   cd iam && terraform init && terraform plan -out tfplan && terraform apply tfplan
   ```

`db-primary` is protected by `prevent_destroy` and EC2 termination protection. To delete it on purpose, first set `prevent_destroy = false` in the tfvars and handle the address move (see NOTES.md).
