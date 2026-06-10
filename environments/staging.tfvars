# -----------------------------------------------------------------------------
# Staging Environment
# -----------------------------------------------------------------------------

project     = "kazi"
environment = "staging"
aws_region  = "af-south-1"

# VPC
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.20.0/24"]
nat_gateway_count    = 1 # single NAT for staging (~$40/mo saving); production default is 2

# Container images — updated by CI/CD pipeline
frontend_image = "public.ecr.aws/nginx/nginx:latest"
backend_image  = "public.ecr.aws/nginx/nginx:latest"
gateway_image  = "public.ecr.aws/nginx/nginx:latest"
portal_image   = "public.ecr.aws/nginx/nginx:latest"
keycloak_image = "public.ecr.aws/nginx/nginx:latest"

# DNS — hosted_zone_id: fill from `aws route53 list-hosted-zones-by-name --dns-name heykazi.com`
# before the first terraform apply (manual step B3 in the deployment plan)
create_dns     = true
domain_name    = "heykazi.com"
hosted_zone_id = ""

# ALB Routing Domains
app_domain    = "staging-app.heykazi.com"
portal_domain = "staging-portal.heykazi.com"
auth_domain   = "staging-auth.heykazi.com"

# ALB Protection
alb_deletion_protection = false

# Monitoring
log_retention_days = 30
alert_email        = "founder@heykazi.com"

# Secrets
secrets_recovery_window = 7

# Auto Scaling
autoscaling_min_capacity = 1
autoscaling_max_capacity = 4

# Compute — Fargate Spot (~70% cheaper; tasks can be reclaimed with 2-min warning)
use_fargate_spot = true

# SSM bastion for DB client access (DBeaver via Session Manager port forward)
create_bastion = true

# Email — capture mode: all email lands in Mailpit (staging-mail.heykazi.com,
# basic auth from the mailpit-ui-auth secret). Switch to "ses" for real delivery,
# then re-run the Keycloak realm SMTP bootstrap step with SES values.
email_mode = "capture"

# RDS
rds_instance_class      = "db.t4g.micro"
rds_multi_az            = false
rds_backup_retention    = 1
rds_deletion_protection = false
rds_skip_final_snapshot = true

# Redis
redis_node_type = "cache.t4g.micro"

# GitHub OIDC
github_repo               = "rakheen-dama/b2b-strawman"
terraform_lock_table_name = "binarymash-terraform-locks"
