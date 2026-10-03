###############################################################################
# Task 4 - least-privilege policy for the ci user (Account A)
###############################################################################

resource "aws_iam_policy" "ci_pipeline" {
  provider    = aws.account_a
  name        = "ci-pipeline-least-privilege"
  description = "ECR push to one repo, ECS deploy to one service, read one artifacts bucket"

  policy = templatefile("${path.module}/policies/ci-least-privilege.json.tftpl", {
    region                = var.region
    account_id            = var.account_a_id
    ecr_repository        = var.ci_ecr_repository_name
    ecs_cluster           = var.ci_ecs_cluster_name
    ecs_service           = var.ci_ecs_service_name
    task_role_arns        = [for r in var.ci_ecs_task_role_names : "arn:aws:iam::${var.account_a_id}:role/${r}"]
    artifacts_bucket_name = var.ci_artifacts_bucket_name
  })
}

resource "aws_iam_user_policy_attachment" "ci_pipeline" {
  provider   = aws.account_a
  user       = aws_iam_user.group1["ci"].name
  policy_arn = aws_iam_policy.ci_pipeline.arn
}
