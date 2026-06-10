# -----------------------------------------------------------------------------
# Production Environment
# -----------------------------------------------------------------------------

project     = "kazi"
environment = "production"
aws_region  = "af-south-1"

# VPC
vpc_cidr             = "10.2.0.0/16"
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs = ["10.2.10.0/24", "10.2.20.0/24"]

# Container images — updated by CI/CD pipeline
frontend_image = "public.ecr.aws/nginx/nginx:latest"
backend_image  = "public.ecr.aws/nginx/nginx:latest"
gateway_image  = "public.ecr.aws/nginx/nginx:latest"
portal_image   = "public.ecr.aws/nginx/nginx:latest"
keycloak_image = "public.ecr.aws/nginx/nginx:latest"

# DNS — flip create_dns to true and fill hosted_zone_id when provisioning production
create_dns     = false
domain_name    = "heykazi.com"
hosted_zone_id = ""

# ALB Routing Domains
app_domain    = "app.heykazi.com"
portal_domain = "portal.heykazi.com"
auth_domain   = "auth.heykazi.com"

# ALB Protection
alb_deletion_protection = true

# Monitoring
log_retention_days = 90
alert_email        = "founder@heykazi.com"

# Secrets
secrets_recovery_window = 30

# Auto Scaling
autoscaling_min_capacity = 2
autoscaling_max_capacity = 10

# Email — production always sends for real via SES
email_mode = "ses"

# RDS
rds_instance_class      = "db.t4g.medium"
rds_multi_az            = true
rds_backup_retention    = 7
rds_deletion_protection = true
rds_skip_final_snapshot = false

# Redis
redis_node_type = "cache.t4g.micro"

# GitHub OIDC
github_repo               = "rakheen-dama/b2b-strawman"
terraform_lock_table_name = "binarymash-terraform-locks"
