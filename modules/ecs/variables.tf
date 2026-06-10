variable "project" {
  description = "Project name"
  type        = string
  default     = "kazi"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch logs"
  type        = string
}

# -----------------------------------------------------------------------------
# Domain Configuration
# -----------------------------------------------------------------------------

variable "app_domain" {
  description = "Application domain (e.g., app.binarymash.io)"
  type        = string
}

variable "auth_domain" {
  description = "Auth/Keycloak domain (e.g., auth.binarymash.io)"
  type        = string
}

variable "portal_domain" {
  description = "Portal domain (e.g., portal.binarymash.io)"
  type        = string
}

variable "keycloak_realm" {
  description = "Keycloak realm name"
  type        = string
  default     = "b2mash"
}

# Networking
variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "frontend_sg_id" {
  description = "Security group ID for frontend ECS tasks"
  type        = string
}

variable "backend_sg_id" {
  description = "Security group ID for backend ECS tasks"
  type        = string
}

# ALB Target Groups
variable "frontend_target_group_arn" {
  description = "ARN of the frontend ALB target group"
  type        = string
}

variable "backend_target_group_arn" {
  description = "ARN of the backend ALB target group (public)"
  type        = string
}

variable "backend_internal_tg_arn" {
  description = "ARN of the backend internal ALB target group"
  type        = string
}

# IAM
variable "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "frontend_task_role_arn" {
  description = "ARN of the frontend ECS task role"
  type        = string
}

variable "backend_task_role_arn" {
  description = "ARN of the backend ECS task role"
  type        = string
}

# Container Images
variable "frontend_image" {
  description = "Full ECR image URI with tag for frontend"
  type        = string
}

variable "backend_image" {
  description = "Full ECR image URI with tag for backend"
  type        = string
}

# Monitoring
variable "frontend_log_group_name" {
  description = "CloudWatch log group name for frontend"
  type        = string
}

variable "backend_log_group_name" {
  description = "CloudWatch log group name for backend"
  type        = string
}

# Secrets (ARNs for injection into containers)
variable "database_url_secret_arn" {
  description = "ARN of the database URL secret"
  type        = string
}

variable "database_migration_url_secret_arn" {
  description = "ARN of the database migration URL secret"
  type        = string
}

variable "keycloak_client_secret_arn" {
  description = "ARN of the Keycloak client secret"
  type        = string
}

variable "keycloak_admin_username_arn" {
  description = "ARN of the Keycloak admin console username secret"
  type        = string
}

variable "keycloak_admin_password_arn" {
  description = "ARN of the Keycloak admin console password secret"
  type        = string
}

variable "keycloak_db_username_arn" {
  description = "ARN of the Keycloak database username secret (used as KC_DB_USERNAME)"
  type        = string
}

variable "keycloak_db_password_arn" {
  description = "ARN of the Keycloak database password secret (used as KC_DB_PASSWORD)"
  type        = string
}

variable "gateway_db_username_arn" {
  description = "ARN of the gateway database username secret (for session storage)"
  type        = string
}

variable "gateway_db_password_arn" {
  description = "ARN of the gateway database password secret (for session storage)"
  type        = string
}

variable "redis_auth_token_arn" {
  description = "ARN of the Redis auth token secret"
  type        = string
}

variable "internal_api_key_arn" {
  description = "ARN of the internal API key"
  type        = string
}

# Infrastructure references
variable "redis_host" {
  description = "ElastiCache Redis primary endpoint hostname"
  type        = string
}

variable "rds_endpoint" {
  description = "RDS PostgreSQL endpoint address (for Keycloak DB URL)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for Cloud Map private DNS namespace"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for document storage"
  type        = string
}

# Service Sizing
variable "frontend_cpu" {
  description = "Frontend task CPU units"
  type        = number
  default     = 512
}

variable "frontend_memory" {
  description = "Frontend task memory in MiB"
  type        = number
  default     = 1024
}

variable "backend_cpu" {
  description = "Backend task CPU units"
  type        = number
  default     = 1024
}

variable "backend_memory" {
  description = "Backend task memory in MiB"
  type        = number
  default     = 2048
}

variable "frontend_desired_count" {
  description = "Desired number of frontend tasks"
  type        = number
  default     = 2
}

variable "backend_desired_count" {
  description = "Desired number of backend tasks"
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# New Services — Networking
# -----------------------------------------------------------------------------

variable "gateway_sg_id" {
  description = "Security group ID for gateway ECS tasks"
  type        = string
}

variable "portal_sg_id" {
  description = "Security group ID for portal ECS tasks"
  type        = string
}

variable "keycloak_sg_id" {
  description = "Security group ID for Keycloak ECS tasks"
  type        = string
}

# -----------------------------------------------------------------------------
# New Services — ALB Target Groups
# -----------------------------------------------------------------------------

variable "gateway_target_group_arn" {
  description = "ARN of the gateway ALB target group"
  type        = string
  default     = ""
}

variable "portal_target_group_arn" {
  description = "ARN of the portal ALB target group"
  type        = string
  default     = ""
}

variable "keycloak_target_group_arn" {
  description = "ARN of the keycloak ALB target group"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# New Services — IAM Task Roles
# -----------------------------------------------------------------------------

variable "gateway_task_role_arn" {
  description = "ARN of the gateway ECS task role"
  type        = string
}

variable "portal_task_role_arn" {
  description = "ARN of the portal ECS task role"
  type        = string
}

variable "keycloak_task_role_arn" {
  description = "ARN of the Keycloak ECS task role"
  type        = string
}

# -----------------------------------------------------------------------------
# New Services — Container Images
# -----------------------------------------------------------------------------

variable "gateway_image" {
  description = "Full ECR image URI with tag for gateway"
  type        = string
}

variable "portal_image" {
  description = "Full ECR image URI with tag for portal"
  type        = string
}

variable "keycloak_image" {
  description = "Full ECR image URI with tag for keycloak"
  type        = string
}

# -----------------------------------------------------------------------------
# New Services — Monitoring
# -----------------------------------------------------------------------------

variable "gateway_log_group_name" {
  description = "CloudWatch log group name for gateway"
  type        = string
}

variable "portal_log_group_name" {
  description = "CloudWatch log group name for portal"
  type        = string
}

variable "keycloak_log_group_name" {
  description = "CloudWatch log group name for keycloak"
  type        = string
}

# -----------------------------------------------------------------------------
# New Services — Sizing
# -----------------------------------------------------------------------------

variable "gateway_cpu" {
  description = "Gateway task CPU units"
  type        = number
  default     = 1024
}

variable "gateway_memory" {
  description = "Gateway task memory in MiB"
  type        = number
  default     = 2048
}

variable "portal_cpu" {
  description = "Portal task CPU units"
  type        = number
  default     = 512
}

variable "portal_memory" {
  description = "Portal task memory in MiB"
  type        = number
  default     = 1024
}

variable "keycloak_cpu" {
  description = "Keycloak task CPU units"
  type        = number
  default     = 1024
}

variable "keycloak_memory" {
  description = "Keycloak task memory in MiB"
  type        = number
  default     = 2048
}

variable "gateway_desired_count" {
  description = "Desired number of gateway tasks"
  type        = number
  default     = 1
}

variable "portal_desired_count" {
  description = "Desired number of portal tasks"
  type        = number
  default     = 1
}

variable "keycloak_desired_count" {
  description = "Desired number of Keycloak tasks"
  type        = number
  default     = 1
}

variable "use_fargate_spot" {
  description = "Weight ECS services onto FARGATE_SPOT (staging cost optimization). Production should keep this false."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Backend email + portal secrets (Secrets Manager ARNs)
# -----------------------------------------------------------------------------

variable "portal_jwt_secret_arn" {
  description = "ARN of the portal JWT secret"
  type        = string
}

variable "portal_magic_link_secret_arn" {
  description = "ARN of the portal magic link secret"
  type        = string
}

variable "smtp_username_arn" {
  description = "ARN of the SMTP username secret"
  type        = string
}

variable "smtp_password_arn" {
  description = "ARN of the SMTP password secret"
  type        = string
}

variable "email_unsubscribe_secret_arn" {
  description = "ARN of the email unsubscribe secret"
  type        = string
}

variable "integration_encryption_key_arn" {
  description = "ARN of the integration encryption key secret"
  type        = string
}

# -----------------------------------------------------------------------------
# Backend email + billing configuration
# -----------------------------------------------------------------------------

variable "smtp_host" {
  description = "SMTP host the backend sends through (SES endpoint, or Mailpit in capture mode)"
  type        = string
  default     = "email-smtp.af-south-1.amazonaws.com"
}

variable "smtp_port" {
  description = "SMTP port (587 for SES STARTTLS, 1025 for Mailpit)"
  type        = string
  default     = "587"
}

variable "email_sender_address" {
  description = "From address for transactional email (must be SES-verified when sending for real)"
  type        = string
  default     = "noreply@heykazi.com"
}

variable "payfast_merchant_id" {
  description = "PayFast merchant ID (default: PayFast public sandbox)"
  type        = string
  default     = "10000100"
}

variable "payfast_merchant_key" {
  description = "PayFast merchant key (default: PayFast public sandbox)"
  type        = string
  default     = "46f0cd694581a"
}

variable "payfast_passphrase" {
  description = "PayFast passphrase (default: PayFast public sandbox)"
  type        = string
  default     = "jt7NOE43FZPn"
}

variable "payfast_sandbox" {
  description = "Use the PayFast sandbox endpoint"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Email mode + Mailpit (capture mode)
# -----------------------------------------------------------------------------

variable "email_mode" {
  description = "Email delivery mode: \"ses\" sends real email via SMTP vars; \"capture\" traps everything in the in-VPC Mailpit service"
  type        = string
  default     = "ses"

  validation {
    condition     = contains(["ses", "capture"], var.email_mode)
    error_message = "email_mode must be \"ses\" or \"capture\"."
  }
}

variable "mailpit_image" {
  description = "Mailpit container image"
  type        = string
  default     = "axllent/mailpit:v1.30"
}

variable "mailpit_sg_id" {
  description = "Security group ID for the Mailpit task"
  type        = string
  default     = ""
}

variable "mailpit_target_group_arn" {
  description = "Target group ARN for the Mailpit UI (empty disables the ALB attachment)"
  type        = string
  default     = ""
}

variable "mailpit_log_group_name" {
  description = "CloudWatch log group for Mailpit"
  type        = string
  default     = ""
}

variable "mailpit_ui_auth_arn" {
  description = "Secrets Manager ARN holding the Mailpit UI basic-auth credentials (user:password)"
  type        = string
  default     = ""
}
