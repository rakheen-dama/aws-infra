# -----------------------------------------------------------------------------
# GitHub OIDC provider + GitHub Actions role (persistent layer)
#
# Lives in the persistent layer so CI can push images and run Terraform before
# any runtime infrastructure exists, and keeps working while runtime is torn
# down. The role carries three inline policies:
#   - cicd:       ECR push/pull + ECS deploys + Terraform state (image deploys)
#   - provision:  the infra services Terraform manages (runtime apply/destroy)
#   - iam-scoped: kazi-* role management + PassRole (runtime apply/destroy)
#
# The OIDC provider is ACCOUNT-GLOBAL (one per URL per account): only one
# environment may create it (create_oidc_provider = true); others look it up.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  all_repos = distinct(concat(
    var.github_repo != "" ? [var.github_repo] : [],
    var.github_repos
  ))
  account = data.aws_caller_identity.current.account_id
  region  = data.aws_region.current.region
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project}-${var.environment}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = [for repo in local.all_repos : "repo:${repo}:*"] }
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# Policy 1: image build/deploy CI (b2b-strawman + keycloak-saas workflows)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cicd" {
  # ECR: GetAuthorizationToken is account-level (mandatory wildcard)
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:${local.region}:${local.account}:repository/${var.project}/*"]
  }

  statement {
    sid = "ECSManage"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
    ]
    resources = [
      "arn:aws:ecs:${local.region}:${local.account}:service/${var.project}-*",
      "arn:aws:ecs:${local.region}:${local.account}:task-definition/${var.project}-*",
      "arn:aws:ecs:${local.region}:${local.account}:task/${var.project}-*",
    ]
  }

  # DescribeTaskDefinition does not support resource-level permissions
  statement {
    sid       = "ECSDescribeTaskDef"
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "TerraformStateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.terraform_state_bucket_name}/*"]
  }

  statement {
    sid       = "TerraformStateBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.terraform_state_bucket_name}"]
  }

  statement {
    sid       = "TerraformStateLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:${local.region}:${local.account}:table/${var.terraform_lock_table_name}"]
  }
}

resource "aws_iam_role_policy" "cicd" {
  name   = "${var.project}-${var.environment}-github-actions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.cicd.json
}

# ---------------------------------------------------------------------------
# Policy 2: infrastructure provisioning (terraform plan/apply/destroy from CI)
# Mirrors docs/iam/deploy-user-infra-policy.json
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "provision" {
  statement {
    sid = "InfraServices"
    actions = [
      "ec2:*",
      "ecr:*",
      "elasticloadbalancing:*",
      "rds:*",
      "elasticache:*",
      "logs:*",
      "cloudwatch:*",
      "sns:*",
      "application-autoscaling:*",
      "servicediscovery:*",
      "acm:*",
      "route53:*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ProjectSecrets"
    actions   = ["secretsmanager:*"]
    resources = ["arn:aws:secretsmanager:*:${local.account}:secret:${var.project}/*"]
  }

  statement {
    sid       = "SecretsAccountLevel"
    actions   = ["secretsmanager:ListSecrets", "secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }

  statement {
    sid     = "ProjectBuckets"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.project}-*",
      "arn:aws:s3:::${var.project}-*/*",
    ]
  }

  statement {
    sid       = "SsmAmiLookup"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "provision" {
  name   = "${var.project}-${var.environment}-github-actions-provision"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.provision.json
}

# ---------------------------------------------------------------------------
# Policy 3: scoped IAM management (runtime layer creates kazi-* ECS roles)
# Mirrors docs/iam/deploy-user-iam-policy.json
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "iam_scoped" {
  statement {
    sid = "ProjectRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${local.account}:role/${var.project}-*"]
  }

  statement {
    sid = "ProjectInstanceProfiles"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${local.account}:instance-profile/${var.project}-*"]
  }

  statement {
    sid       = "PassProjectRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account}:role/${var.project}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account}:role/aws-service-role/*"]
  }
}

resource "aws_iam_role_policy" "iam_scoped" {
  name   = "${var.project}-${var.environment}-github-actions-iam"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.iam_scoped.json
}
