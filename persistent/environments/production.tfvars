# -----------------------------------------------------------------------------
# Persistent layer — Production
# -----------------------------------------------------------------------------

project     = "kazi"
environment = "production"
aws_region  = "af-south-1"

# ECR repos + OIDC provider are owned by the staging persistent layer
manage_shared = false

secrets_recovery_window = 30

github_repo  = "rakheen-dama/b2b-strawman"
github_repos = ["rakheen-dama/keycloak-saas", "rakheen-dama/aws-infra"]
