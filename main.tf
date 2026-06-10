# -----------------------------------------------------------------------------
# Root Module — composes all child modules
# -----------------------------------------------------------------------------
# Usage:
#   terraform init -backend-config="key=staging/terraform.tfstate"
#   terraform plan -var-file=environments/staging.tfvars
#   terraform apply -var-file=environments/staging.tfvars
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

module "vpc" {
  source = "./modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  nat_gateway_count    = var.nat_gateway_count
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

module "security_groups" {
  source = "./modules/security-groups"

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
}

# -----------------------------------------------------------------------------
# Data (RDS PostgreSQL + ElastiCache Redis)
# -----------------------------------------------------------------------------

module "data" {
  source = "./modules/data"

  project     = var.project
  environment = var.environment

  # Networking
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Security Groups
  rds_sg_id = module.security_groups.rds_sg_id

  # RDS Configuration
  rds_instance_class      = var.rds_instance_class
  rds_multi_az            = var.rds_multi_az
  rds_storage_gb          = var.rds_storage_gb
  rds_max_storage_gb      = var.rds_max_storage_gb
  rds_backup_retention    = var.rds_backup_retention
  rds_deletion_protection = var.rds_deletion_protection
  rds_skip_final_snapshot = var.rds_skip_final_snapshot

  rds_restore_snapshot_identifier = var.rds_restore_snapshot_identifier

  # Redis Configuration
  redis_sg_id                 = module.security_groups.redis_sg_id
  redis_node_type             = var.redis_node_type
  redis_engine_version        = var.redis_engine_version
  create_redis                = var.create_redis
  redis_auth_token_secret_arn = data.aws_secretsmanager_secret.persistent["redis-auth-token"].arn
}

# -----------------------------------------------------------------------------
# Monitoring (CloudWatch Log Groups, SNS, Alarms)
# -----------------------------------------------------------------------------

module "monitoring" {
  source = "./modules/monitoring"

  project            = var.project
  environment        = var.environment
  log_retention_days = var.log_retention_days
  alert_email        = var.alert_email

  # ALB dimensions for alarms
  alb_arn_suffix         = module.alb.public_alb_arn_suffix
  backend_tg_arn_suffix  = module.alb.backend_tg_arn_suffix
  gateway_tg_arn_suffix  = module.alb.gateway_tg_arn_suffix
  keycloak_tg_arn_suffix = module.alb.keycloak_tg_arn_suffix

  # RDS dimension for alarms
  rds_instance_identifier = module.data.rds_instance_identifier

  # ECS dimensions for alarms
  ecs_cluster_name     = module.ecs.cluster_name
  backend_service_name = module.ecs.backend_service_name
}

# -----------------------------------------------------------------------------
# IAM Roles
# -----------------------------------------------------------------------------

module "iam" {
  source = "./modules/iam"

  project                = var.project
  environment            = var.environment
  ecr_repo_arns          = local.ecr_repo_arns
  s3_bucket_arn          = local.s3_bucket_arn
  secret_arns            = [for s in data.aws_secretsmanager_secret.persistent : s.arn]
  frontend_log_group_arn = module.monitoring.frontend_log_group_arn
  backend_log_group_arn  = module.monitoring.backend_log_group_arn
  gateway_log_group_arn  = module.monitoring.gateway_log_group_arn
  portal_log_group_arn   = module.monitoring.portal_log_group_arn
  keycloak_log_group_arn = module.monitoring.keycloak_log_group_arn
  mailpit_log_group_arn  = module.monitoring.mailpit_log_group_arn
}

# -----------------------------------------------------------------------------
# DNS + ACM (conditional)
# -----------------------------------------------------------------------------

module "dns" {
  source = "./modules/dns"

  project            = var.project
  environment        = var.environment
  create_dns         = var.create_dns
  domain_name        = var.domain_name
  hosted_zone_id     = var.hosted_zone_id
  alb_dns_name       = module.alb.public_alb_dns_name
  alb_zone_id        = module.alb.public_alb_zone_id
  create_mail_record = var.email_mode == "capture"
}

# -----------------------------------------------------------------------------
# Application Load Balancers
# -----------------------------------------------------------------------------

module "alb" {
  source = "./modules/alb"

  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  public_alb_sg_id   = module.security_groups.public_alb_sg_id
  internal_alb_sg_id = module.security_groups.internal_alb_sg_id
  certificate_arn    = module.dns.certificate_arn

  # Domain routing (host-based rules on HTTPS listener)
  # When DNS is managed by the dns module, use its outputs as the source of truth
  # to avoid drift between Route 53 records and ALB listener rules.
  app_domain    = var.create_dns ? module.dns.app_domain : var.app_domain
  portal_domain = var.create_dns ? module.dns.portal_domain : var.portal_domain
  auth_domain   = var.create_dns ? module.dns.auth_domain : var.auth_domain

  # Mailpit UI (email capture mode)
  mailpit_enabled = var.email_mode == "capture"
  mail_domain     = var.create_dns ? module.dns.mail_domain : ""

  # ALB protection
  alb_deletion_protection = var.alb_deletion_protection
}

# -----------------------------------------------------------------------------
# ECS Cluster + Services
# -----------------------------------------------------------------------------

module "ecs" {
  source = "./modules/ecs"

  project          = var.project
  environment      = var.environment
  aws_region       = var.aws_region
  use_fargate_spot = var.use_fargate_spot

  # Networking
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  frontend_sg_id     = module.security_groups.frontend_sg_id
  backend_sg_id      = module.security_groups.backend_sg_id
  gateway_sg_id      = module.security_groups.gateway_sg_id
  portal_sg_id       = module.security_groups.portal_sg_id
  keycloak_sg_id     = module.security_groups.keycloak_sg_id

  # ALB Target Groups
  frontend_target_group_arn = module.alb.frontend_target_group_arn
  backend_target_group_arn  = module.alb.backend_target_group_arn
  backend_internal_tg_arn   = module.alb.backend_internal_target_group_arn
  gateway_target_group_arn  = module.alb.gateway_target_group_arn
  portal_target_group_arn   = module.alb.portal_target_group_arn
  keycloak_target_group_arn = module.alb.keycloak_target_group_arn

  # IAM
  ecs_execution_role_arn = module.iam.ecs_execution_role_arn
  frontend_task_role_arn = module.iam.frontend_task_role_arn
  backend_task_role_arn  = module.iam.backend_task_role_arn
  gateway_task_role_arn  = module.iam.gateway_task_role_arn
  portal_task_role_arn   = module.iam.portal_task_role_arn
  keycloak_task_role_arn = module.iam.keycloak_task_role_arn

  # Container Images
  frontend_image = local.frontend_image
  backend_image  = local.backend_image
  gateway_image  = local.gateway_image
  portal_image   = local.portal_image
  keycloak_image = local.keycloak_image

  # Monitoring
  frontend_log_group_name = module.monitoring.frontend_log_group_name
  backend_log_group_name  = module.monitoring.backend_log_group_name
  gateway_log_group_name  = module.monitoring.gateway_log_group_name
  portal_log_group_name   = module.monitoring.portal_log_group_name
  keycloak_log_group_name = module.monitoring.keycloak_log_group_name

  # Secrets
  database_url_secret_arn           = data.aws_secretsmanager_secret.persistent["database-url"].arn
  database_migration_url_secret_arn = data.aws_secretsmanager_secret.persistent["database-migration-url"].arn
  internal_api_key_arn              = data.aws_secretsmanager_secret.persistent["internal-api-key"].arn
  keycloak_client_secret_arn        = data.aws_secretsmanager_secret.persistent["keycloak-client-secret"].arn
  keycloak_admin_username_arn       = data.aws_secretsmanager_secret.persistent["keycloak-admin-username"].arn
  keycloak_admin_password_arn       = data.aws_secretsmanager_secret.persistent["keycloak-admin-password"].arn
  keycloak_db_username_arn          = data.aws_secretsmanager_secret.persistent["keycloak-db-username"].arn
  keycloak_db_password_arn          = data.aws_secretsmanager_secret.persistent["keycloak-db-password"].arn
  gateway_db_username_arn           = data.aws_secretsmanager_secret.persistent["gateway-db-username"].arn
  gateway_db_password_arn           = data.aws_secretsmanager_secret.persistent["gateway-db-password"].arn
  redis_auth_token_arn              = data.aws_secretsmanager_secret.persistent["redis-auth-token"].arn
  portal_jwt_secret_arn             = data.aws_secretsmanager_secret.persistent["portal-jwt-secret"].arn
  portal_magic_link_secret_arn      = data.aws_secretsmanager_secret.persistent["portal-magic-link-secret"].arn
  smtp_username_arn                 = data.aws_secretsmanager_secret.persistent["smtp-username"].arn
  smtp_password_arn                 = data.aws_secretsmanager_secret.persistent["smtp-password"].arn
  email_unsubscribe_secret_arn      = data.aws_secretsmanager_secret.persistent["email-unsubscribe-secret"].arn
  integration_encryption_key_arn    = data.aws_secretsmanager_secret.persistent["integration-encryption-key"].arn

  # Infrastructure endpoints
  redis_host   = module.data.redis_endpoint
  rds_endpoint = module.data.rds_endpoint

  # App Config
  s3_bucket_name = local.s3_bucket_name

  # Email + billing
  smtp_host            = var.smtp_host
  smtp_port            = var.smtp_port
  email_sender_address = var.email_sender_address
  payfast_merchant_id  = var.payfast_merchant_id
  payfast_merchant_key = var.payfast_merchant_key
  payfast_passphrase   = var.payfast_passphrase
  payfast_sandbox      = var.payfast_sandbox

  # Email capture (Mailpit)
  email_mode               = var.email_mode
  mailpit_image            = var.mailpit_image
  mailpit_sg_id            = module.security_groups.mailpit_sg_id
  mailpit_target_group_arn = module.alb.mailpit_target_group_arn
  mailpit_log_group_name   = module.monitoring.mailpit_log_group_name
  mailpit_ui_auth_arn      = data.aws_secretsmanager_secret.persistent["mailpit-ui-auth"].arn

  # Domain routing (parameterized — no hardcoded domains in ECS task defs)
  app_domain     = var.create_dns ? module.dns.app_domain : var.app_domain
  portal_domain  = var.create_dns ? module.dns.portal_domain : var.portal_domain
  auth_domain    = var.create_dns ? module.dns.auth_domain : var.auth_domain
  keycloak_realm = var.keycloak_realm
}

# -----------------------------------------------------------------------------
# Auto Scaling
# -----------------------------------------------------------------------------

module "autoscaling" {
  source = "./modules/autoscaling"

  project               = var.project
  environment           = var.environment
  ecs_cluster_name      = module.ecs.cluster_name
  frontend_service_name = module.ecs.frontend_service_name
  backend_service_name  = module.ecs.backend_service_name
  min_capacity          = var.autoscaling_min_capacity
  max_capacity          = var.autoscaling_max_capacity

  # New services
  gateway_service_name = module.ecs.gateway_service_name
  portal_service_name  = module.ecs.portal_service_name
  gateway_min_capacity = 1
  gateway_max_capacity = 2
  portal_min_capacity  = 1
  portal_max_capacity  = 2
}

# -----------------------------------------------------------------------------
# SSM Bastion (optional — DB client access via Session Manager port forwarding)
# -----------------------------------------------------------------------------

module "bastion" {
  source = "./modules/bastion"
  count  = var.create_bastion ? 1 : 0

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  subnet_id   = module.vpc.private_subnet_ids[0]
  rds_sg_id   = module.security_groups.rds_sg_id
  redis_sg_id = module.security_groups.redis_sg_id
}
