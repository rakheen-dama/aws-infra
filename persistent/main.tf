# -----------------------------------------------------------------------------
# Persistent layer — survives runtime teardown (env-down.sh)
#
# Contents: ECR repositories + images, Secrets Manager values, the S3 app
# bucket, and the GitHub OIDC provider + Actions role. ~$10/mo when the
# runtime layer is destroyed.
#
# Usage:
#   cd persistent/
#   terraform init -backend-config="key=staging/persistent.tfstate"
#   terraform plan  -var-file=environments/staging.tfvars
#   terraform apply -var-file=environments/staging.tfvars
#
# Applied ONCE per environment, before anything else. Never destroyed as part
# of the down/up cycle. The runtime root (../) consumes these resources via
# data sources and naming convention, NOT remote state.
#
# NOTE: ECR repos (kazi/<svc>) and the GitHub OIDC provider are shared across
# environments — only the environment with manage_shared = true creates them
# (staging). A future production persistent layer sets manage_shared = false.
# -----------------------------------------------------------------------------

module "ecr" {
  source = "../modules/ecr"
  count  = var.manage_shared ? 1 : 0

  project     = var.project
  environment = var.environment
}

module "s3" {
  source = "../modules/s3"

  project     = var.project
  environment = var.environment
}

module "secrets" {
  source = "../modules/secrets"

  project                 = var.project
  environment             = var.environment
  recovery_window_in_days = var.secrets_recovery_window
}

module "github_oidc" {
  source = "../modules/github-oidc"

  project                     = var.project
  environment                 = var.environment
  create_oidc_provider        = var.manage_shared
  github_repo                 = var.github_repo
  github_repos                = var.github_repos
  terraform_state_bucket_name = var.terraform_state_bucket_name
  terraform_lock_table_name   = var.terraform_lock_table_name
}
