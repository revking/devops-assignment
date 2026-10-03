###############################################################################
# Account A - groups, users, roleA, roleB
###############################################################################

locals {
  account_a_root = "arn:aws:iam::${var.account_a_id}:root"
  group2_arns    = [for u in aws_iam_user.group2 : u.arn]
}

# ---------------------------------------------------------------- users -----

resource "aws_iam_user" "group1" {
  provider = aws.account_a
  for_each = var.group1_users

  name = each.key
  path = "/programmatic/"
  tags = { AccessType = "programmatic-only" }
}

resource "aws_iam_user" "group2" {
  provider = aws.account_a
  for_each = var.group2_users

  name          = each.key
  path          = "/humans/"
  force_destroy = true
  tags          = { AccessType = "console-and-cli" }
}

# Credentials are only created when a PGP key is supplied, so Terraform state
# holds ciphertext, never plaintext secrets. NOTES.md explains why I would not
# hand long-lived keys to engine/ci in production at all.
resource "aws_iam_access_key" "group1" {
  provider = aws.account_a
  for_each = var.pgp_key == null ? toset([]) : var.group1_users

  user    = aws_iam_user.group1[each.key].name
  pgp_key = var.pgp_key
}

resource "aws_iam_user_login_profile" "group2" {
  provider = aws.account_a
  for_each = var.pgp_key == null ? toset([]) : var.group2_users

  user                    = aws_iam_user.group2[each.key].name
  pgp_key                 = var.pgp_key
  password_reset_required = true

  lifecycle {
    ignore_changes = [password_length, password_reset_required, pgp_key]
  }
}

# --------------------------------------------------------------- group1 -----
# CLI/programmatic only: members get no login profile, and this guardrail stops
# a member (or a leaked key with broader rights) from creating one later.

resource "aws_iam_group" "group1" {
  provider = aws.account_a
  name     = "group1"
}

resource "aws_iam_group_membership" "group1" {
  provider = aws.account_a
  name     = "group1-membership"
  group    = aws_iam_group.group1.name
  users    = [for u in aws_iam_user.group1 : u.name]
}

resource "aws_iam_group_policy" "group1_programmatic_only" {
  provider = aws.account_a
  name     = "programmatic-only-guardrail"
  group    = aws_iam_group.group1.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyConsolePasswordManagement"
      Effect = "Deny"
      Action = [
        "iam:CreateLoginProfile",
        "iam:UpdateLoginProfile",
        "iam:DeleteLoginProfile",
      ]
      Resource = "*"
    }]
  })
}

# --------------------------------------------------------------- group2 -----
# Console + CLI. Members manage their own password, MFA device and access keys;
# everything else is denied until they authenticate with MFA. Admin work is done
# by assuming roleA (MFA required).

resource "aws_iam_group" "group2" {
  provider = aws.account_a
  name     = "group2"
}

resource "aws_iam_group_membership" "group2" {
  provider = aws.account_a
  name     = "group2-membership"
  group    = aws_iam_group.group2.name
  users    = [for u in aws_iam_user.group2 : u.name]
}

resource "aws_iam_group_policy" "group2_console_cli" {
  provider = aws.account_a
  name     = "console-cli-self-service-mfa"
  group    = aws_iam_group.group2.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ViewAccountInfo"
        Effect = "Allow"
        Action = [
          "iam:GetAccountPasswordPolicy",
          "iam:GetAccountSummary",
          "iam:ListVirtualMFADevices",
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageOwnCredentials"
        Effect = "Allow"
        Action = [
          "iam:ChangePassword",
          "iam:GetUser",
          "iam:GetLoginProfile",
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey",
          "iam:GetAccessKeyLastUsed",
          "iam:ListMFADevices",
          "iam:EnableMFADevice",
          "iam:ResyncMFADevice",
          "iam:DeactivateMFADevice",
        ]
        Resource = "arn:aws:iam::${var.account_a_id}:user/humans/$${aws:username}"
      },
      {
        Sid    = "ManageOwnVirtualMFA"
        Effect = "Allow"
        Action = [
          "iam:CreateVirtualMFADevice",
          "iam:DeleteVirtualMFADevice",
        ]
        Resource = "arn:aws:iam::${var.account_a_id}:mfa/$${aws:username}"
      },
      {
        Sid      = "AssumeWorkRolesWithMFA"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = [aws_iam_role.roleA.arn, aws_iam_role.roleB.arn]
        Condition = {
          Bool = { "aws:MultiFactorAuthPresent" = "true" }
        }
      },
      {
        Sid    = "DenyAllExceptMFASetupWithoutMFA"
        Effect = "Deny"
        NotAction = [
          "iam:ChangePassword",
          "iam:GetUser",
          "iam:ListMFADevices",
          "iam:ListVirtualMFADevices",
          "iam:CreateVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:ResyncMFADevice",
          "sts:GetSessionToken",
        ]
        Resource = "*"
        Condition = {
          BoolIfExists = { "aws:MultiFactorAuthPresent" = "false" }
        }
      },
    ]
  })
}

# ---------------------------------------------------------------- roleA -----
# Administrative access to every AWS service except IAM.

resource "aws_iam_role" "roleA" {
  provider             = aws.account_a
  name                 = "roleA"
  description          = "Administrator for all AWS services except IAM"
  max_session_duration = 3600

  # Trust only the named group2 humans, and only with MFA. The principal is the
  # account narrowed by aws:PrincipalArn: condition values are plain strings,
  # whereas a user ARN in Principal is resolved to a unique ID and silently
  # breaks if the user is ever deleted and re-created.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "Group2HumansWithMFA"
      Effect    = "Allow"
      Principal = { AWS = local.account_a_root }
      Action    = "sts:AssumeRole"
      Condition = {
        Bool      = { "aws:MultiFactorAuthPresent" = "true" }
        ArnEquals = { "aws:PrincipalArn" = local.group2_arns }
      }
    }]
  })
}

resource "aws_iam_role_policy" "roleA_admin_no_iam" {
  provider = aws.account_a
  name     = "admin-except-iam"
  role     = aws_iam_role.roleA.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEverythingExceptIAM"
        Effect    = "Allow"
        NotAction = ["iam:*"]
        Resource  = "*"
      },
      {
        # Many services create their service-linked role on first use. SLR
        # permissions are fixed by AWS, so this cannot escalate privileges.
        # Deliberate, documented exception (NOTES.md, Task 3).
        Sid      = "AllowServiceLinkedRoles"
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "arn:aws:iam::*:role/aws-service-role/*"
      },
    ]
  })
}

# ---------------------------------------------------------------- roleB -----
# Its only permission is to assume roleC in Account B.

resource "aws_iam_role" "roleB" {
  provider             = aws.account_a
  name                 = "roleB"
  description          = "Cross-account hop into Account B roleC; no other permissions"
  max_session_duration = 3600

  # Who may use the hop: the engine automation user, and group2 humans with MFA.
  # ci is intentionally not trusted - its permissions are fixed by Task 4.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EngineAutomation"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_user.group1["engine"].arn }
        Action    = "sts:AssumeRole"
      },
      {
        Sid       = "Group2HumansWithMFA"
        Effect    = "Allow"
        Principal = { AWS = local.account_a_root }
        Action    = "sts:AssumeRole"
        Condition = {
          Bool      = { "aws:MultiFactorAuthPresent" = "true" }
          ArnEquals = { "aws:PrincipalArn" = local.group2_arns }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "roleB_assume_roleC" {
  provider = aws.account_a
  name     = "assume-roleC-only"
  role     = aws_iam_role.roleB.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeRoleCInAccountB"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::${var.account_b_id}:role/roleC"
    }]
  })
}
