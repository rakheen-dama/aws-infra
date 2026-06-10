variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "kazi"
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "create_oidc_provider" {
  description = "Create the account-global GitHub OIDC provider (exactly one environment may do this; others look it up)"
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "Primary GitHub repository allowed to assume the role (org/repo)"
  type        = string
  default     = ""
}

variable "github_repos" {
  description = "Additional GitHub repositories allowed to assume the role"
  type        = list(string)
  default     = []
}

variable "terraform_state_bucket_name" {
  description = "S3 bucket holding Terraform state"
  type        = string
}

variable "terraform_lock_table_name" {
  description = "DynamoDB table for Terraform state locking"
  type        = string
}
