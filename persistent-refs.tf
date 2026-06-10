# -----------------------------------------------------------------------------
# References into the persistent layer (persistent/ root, separate state)
#
# The runtime layer consumes persistent resources via data sources and naming
# convention — NOT terraform_remote_state — so the two layers stay loosely
# coupled. The persistent layer must be applied before the first runtime plan
# (the secret data sources fail on missing secrets).
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  persistent_secret_names = [
    "database-url",
    "database-migration-url",
    "internal-api-key",
    "keycloak-client-id",
    "keycloak-client-secret",
    "keycloak-admin-username",
    "keycloak-admin-password",
    "portal-jwt-secret",
    "portal-magic-link-secret",
    "integration-encryption-key",
    "smtp-username",
    "smtp-password",
    "email-unsubscribe-secret",
    "keycloak-db-username",
    "keycloak-db-password",
    "gateway-db-username",
    "gateway-db-password",
    "redis-auth-token",
    "mailpit-ui-auth",
  ]

  ecr_services = ["frontend", "backend", "gateway", "portal", "keycloak"]
  ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  ecr_repo_arns = [
    for svc in local.ecr_services :
    "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project}/${svc}"
  ]

  # Images default to the conventionally-tagged ECR image (seeded by the
  # seed-images workflow); a non-empty *_image variable overrides.
  image_tag      = var.environment == "production" ? "production" : "staging"
  frontend_image = var.frontend_image != "" ? var.frontend_image : "${local.ecr_registry}/${var.project}/frontend:${local.image_tag}"
  backend_image  = var.backend_image != "" ? var.backend_image : "${local.ecr_registry}/${var.project}/backend:${local.image_tag}"
  gateway_image  = var.gateway_image != "" ? var.gateway_image : "${local.ecr_registry}/${var.project}/gateway:${local.image_tag}"
  portal_image   = var.portal_image != "" ? var.portal_image : "${local.ecr_registry}/${var.project}/portal:${local.image_tag}"
  keycloak_image = var.keycloak_image != "" ? var.keycloak_image : "${local.ecr_registry}/${var.project}/keycloak:${local.image_tag}"

  # App document bucket (modules/s3 in the persistent layer): kazi-<env>
  s3_bucket_name = "${var.project}-${var.environment}"
  s3_bucket_arn  = "arn:aws:s3:::${local.s3_bucket_name}"
}

data "aws_secretsmanager_secret" "persistent" {
  for_each = toset(local.persistent_secret_names)

  name = "${var.project}/${var.environment}/${each.key}"
}
