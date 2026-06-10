variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "kazi"
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "af-south-1"
}

variable "manage_shared" {
  description = "Manage cross-environment singletons (ECR repos, GitHub OIDC provider). Exactly one environment sets this true."
  type        = bool
  default     = false
}

variable "secrets_recovery_window" {
  description = "Secrets Manager recovery window in days"
  type        = number
  default     = 7
}

variable "github_repo" {
  description = "Primary GitHub repository allowed to assume the CI role (org/repo)"
  type        = string
  default     = ""
}

variable "github_repos" {
  description = "Additional GitHub repositories allowed to assume the CI role"
  type        = list(string)
  default     = ["rakheen-dama/keycloak-saas", "rakheen-dama/aws-infra"]
}

variable "terraform_state_bucket_name" {
  description = "S3 bucket holding Terraform state"
  type        = string
  default     = "binarymash-terraform-state"
}

variable "terraform_lock_table_name" {
  description = "DynamoDB table for Terraform state locking"
  type        = string
  default     = "binarymash-terraform-locks"
}
