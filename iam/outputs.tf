output "roleA_arn" {
  description = "Admin-except-IAM role in Account A."
  value       = aws_iam_role.roleA.arn
}

output "roleB_arn" {
  description = "Cross-account hop role in Account A."
  value       = aws_iam_role.roleB.arn
}

output "roleC_arn" {
  description = "Bucket-access role in Account B."
  value       = aws_iam_role.roleC.arn
}

output "ci_policy_arn" {
  description = "Least-privilege policy attached to the ci user."
  value       = aws_iam_policy.ci_pipeline.arn
}

output "group2_encrypted_passwords" {
  description = "PGP-encrypted initial console passwords (empty when pgp_key is null)."
  value       = { for u, p in aws_iam_user_login_profile.group2 : u => p.encrypted_password }
}

output "group1_access_keys" {
  description = "Access key IDs and PGP-encrypted secrets (empty when pgp_key is null)."
  value = {
    for u, k in aws_iam_access_key.group1 : u => {
      id               = k.id
      encrypted_secret = k.encrypted_secret
    }
  }
}
