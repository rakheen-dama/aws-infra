# -----------------------------------------------------------------------------
# Persistent layer — Staging
# -----------------------------------------------------------------------------

project     = "kazi"
environment = "staging"
aws_region  = "af-south-1"

# Staging owns the cross-environment singletons (ECR repos, GitHub OIDC provider)
manage_shared = true

secrets_recovery_window = 7

github_repo  = "rakheen-dama/b2b-strawman"
github_repos = ["rakheen-dama/keycloak-saas", "rakheen-dama/aws-infra"]
