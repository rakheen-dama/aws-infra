# -----------------------------------------------------------------------------
# ECS Cluster with Fargate and Container Insights
# -----------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

locals {
  email_capture = var.email_mode == "capture"

  # Capture mode relays through the in-VPC Mailpit service: plain SMTP, no auth,
  # no STARTTLS. SMTP_AUTH / SMTP_STARTTLS are read by the backend's
  # application.yml placeholders (spring.mail.properties.mail.smtp.*, defaults
  # true) — plain env names on purpose, to avoid relying on Spring relaxed
  # binding of map keys. SMTP_USERNAME / SMTP_PASSWORD secrets stay injected
  # but are ignored when auth is false.
  backend_smtp_env = local.email_capture ? [
    { name = "SMTP_HOST", value = "mailpit.kazi.internal" },
    { name = "SMTP_PORT", value = "1025" },
    { name = "SMTP_AUTH", value = "false" },
    { name = "SMTP_STARTTLS", value = "false" },
    ] : [
    { name = "SMTP_HOST", value = var.smtp_host },
    { name = "SMTP_PORT", value = var.smtp_port },
  ]
}

# -----------------------------------------------------------------------------
# Frontend Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project}-${var.environment}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.frontend_cpu
  memory                   = var.frontend_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.frontend_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = var.frontend_image
      essential = true

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NEXT_PUBLIC_AUTH_MODE", value = "keycloak" },
        { name = "NEXT_PUBLIC_GATEWAY_URL", value = "https://${var.app_domain}" },
        { name = "GATEWAY_URL", value = "https://${var.app_domain}" },
        { name = "BACKEND_URL", value = "http://backend.kazi.internal:8080" },
        { name = "NODE_ENV", value = "production" },
      ]

      secrets = [
        { name = "INTERNAL_API_KEY", valueFrom = var.internal_api_key_arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.frontend_log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# Backend Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project}-${var.environment}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.backend_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = var.backend_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = concat([
        # "prod" deliberately, not var.environment — there is no application-staging.yml;
        # staging runs the prod profile and differs via env vars only
        { name = "SPRING_PROFILES_ACTIVE", value = "prod,keycloak" },
        { name = "AWS_S3_BUCKET", value = var.s3_bucket_name },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "JWT_ISSUER_URI", value = "https://${var.auth_domain}/realms/${var.keycloak_realm}" },
        { name = "JWT_JWK_SET_URI", value = "https://${var.auth_domain}/realms/${var.keycloak_realm}/protocol/openid-connect/certs" },
        { name = "KEYCLOAK_AUTH_SERVER_URL", value = "https://${var.auth_domain}" },
        { name = "KEYCLOAK_REALM", value = var.keycloak_realm },
        { name = "SPRING_FLYWAY_ENABLED", value = "true" },
        { name = "EMAIL_SENDER_ADDRESS", value = var.email_sender_address },
        { name = "APP_BASE_URL", value = "https://${var.app_domain}" },
        { name = "PORTAL_BASE_URL", value = "https://${var.portal_domain}" },
        # heykazi.billing has no-default placeholders — backend fails to boot without these.
        # /api/* on the public ALB routes to the backend, so the PayFast notify URL base
        # is the app domain.
        { name = "HEYKAZI_BASE_URL", value = "https://${var.app_domain}" },
        { name = "HEYKAZI_FRONTEND_URL", value = "https://${var.app_domain}" },
        # PayFast public sandbox credentials — not sensitive. Move to Secrets Manager
        # before enabling real billing in production.
        { name = "PAYFAST_MERCHANT_ID", value = var.payfast_merchant_id },
        { name = "PAYFAST_MERCHANT_KEY", value = var.payfast_merchant_key },
        { name = "PAYFAST_PASSPHRASE", value = var.payfast_passphrase },
        { name = "PAYFAST_SANDBOX", value = var.payfast_sandbox ? "true" : "false" },
      ], local.backend_smtp_env)

      secrets = [
        { name = "DATABASE_URL", valueFrom = var.database_url_secret_arn },
        { name = "DATABASE_MIGRATION_URL", valueFrom = var.database_migration_url_secret_arn },
        { name = "INTERNAL_API_KEY", valueFrom = var.internal_api_key_arn },
        { name = "KEYCLOAK_ADMIN_USERNAME", valueFrom = var.keycloak_admin_username_arn },
        { name = "KEYCLOAK_ADMIN_PASSWORD", valueFrom = var.keycloak_admin_password_arn },
        { name = "KEYCLOAK_CLIENT_SECRET", valueFrom = var.keycloak_client_secret_arn },
        { name = "PORTAL_JWT_SECRET", valueFrom = var.portal_jwt_secret_arn },
        { name = "PORTAL_MAGIC_LINK_SECRET", valueFrom = var.portal_magic_link_secret_arn },
        { name = "SMTP_USERNAME", valueFrom = var.smtp_username_arn },
        { name = "SMTP_PASSWORD", valueFrom = var.smtp_password_arn },
        { name = "EMAIL_UNSUBSCRIBE_SECRET", valueFrom = var.email_unsubscribe_secret_arn },
        { name = "INTEGRATION_ENCRYPTION_KEY", valueFrom = var.integration_encryption_key_arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.backend_log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# Frontend Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "frontend" {
  name            = "${var.project}-${var.environment}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_desired_count

  # Spot-weighted (4:1) when use_fargate_spot, plain FARGATE otherwise — same for all 5 services
  dynamic "capacity_provider_strategy" {
    for_each = var.use_fargate_spot ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 4
    }
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = var.use_fargate_spot ? 0 : 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.frontend_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.frontend_target_group_arn
    container_name   = "frontend"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# -----------------------------------------------------------------------------
# Gateway Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "gateway" {
  family                   = "${var.project}-${var.environment}-gateway"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.gateway_cpu
  memory                   = var.gateway_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.gateway_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "gateway"
      image     = var.gateway_image
      essential = true

      portMappings = [
        {
          containerPort = 8443
          protocol      = "tcp"
        }
      ]

      environment = [
        # Activates application-production.yml (Redis sessions). Without this the
        # gateway silently falls back to JDBC sessions.
        { name = "SPRING_PROFILES_ACTIVE", value = "production" },
        { name = "BACKEND_URL", value = "http://backend.kazi.internal:8080" },
        { name = "KEYCLOAK_ISSUER", value = "https://${var.auth_domain}/realms/${var.keycloak_realm}" },
        { name = "KEYCLOAK_CLIENT_ID", value = "gateway-bff" },
        { name = "FRONTEND_URL", value = "https://${var.app_domain}" },
        { name = "DB_HOST", value = var.rds_endpoint },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "kazi" },
        { name = "CORS_ALLOWED_ORIGINS", value = "https://${var.app_domain},https://${var.portal_domain}" },
        # Names must match gateway application-production.yml (spring.data.redis.*)
        { name = "SPRING_DATA_REDIS_HOST", value = var.redis_host },
      ]

      secrets = [
        { name = "KEYCLOAK_CLIENT_SECRET", valueFrom = var.keycloak_client_secret_arn },
        { name = "DB_USER", valueFrom = var.gateway_db_username_arn },
        { name = "DB_PASSWORD", valueFrom = var.gateway_db_password_arn },
        { name = "SPRING_DATA_REDIS_PASSWORD", valueFrom = var.redis_auth_token_arn },
        { name = "INTERNAL_API_KEY", valueFrom = var.internal_api_key_arn },
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8443/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.gateway_log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# Portal Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "portal" {
  family                   = "${var.project}-${var.environment}-portal"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.portal_cpu
  memory                   = var.portal_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.portal_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "portal"
      image     = var.portal_image
      essential = true

      portMappings = [
        {
          containerPort = 3002
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NEXT_PUBLIC_PORTAL_API_URL", value = "https://${var.portal_domain}/api" },
        { name = "NODE_ENV", value = "production" },
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:3002/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.portal_log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# Keycloak Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "keycloak" {
  family                   = "${var.project}-${var.environment}-keycloak"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.keycloak_cpu
  memory                   = var.keycloak_memory
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.keycloak_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "keycloak"
      image     = var.keycloak_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "KC_DB", value = "postgres" },
        # Database created manually at provisioning (deployment plan step B5)
        { name = "KC_DB_URL", value = "jdbc:postgresql://${var.rds_endpoint}:5432/kazi_keycloak" },
        { name = "KC_HOSTNAME", value = var.auth_domain },
        { name = "KC_PROXY_HEADERS", value = "xforwarded" },
        { name = "KC_HEALTH_ENABLED", value = "true" },
      ]

      secrets = [
        { name = "KC_DB_USERNAME", valueFrom = var.keycloak_db_username_arn },
        { name = "KC_DB_PASSWORD", valueFrom = var.keycloak_db_password_arn },
        { name = "KEYCLOAK_ADMIN", valueFrom = var.keycloak_admin_username_arn },
        { name = "KEYCLOAK_ADMIN_PASSWORD", valueFrom = var.keycloak_admin_password_arn },
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health/ready || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 120
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.keycloak_log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# Cloud Map — private DNS namespace kazi.internal
# -----------------------------------------------------------------------------

resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "kazi.internal"
  description = "Private DNS namespace for internal service discovery"
  vpc         = var.vpc_id

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_service_discovery_service" "backend" {
  name = "backend"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# -----------------------------------------------------------------------------
# Backend Service — registers with both public and internal target groups
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "backend" {
  name                              = "${var.project}-${var.environment}-backend"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.backend.arn
  desired_count                     = var.backend_desired_count
  health_check_grace_period_seconds = 180

  dynamic "capacity_provider_strategy" {
    for_each = var.use_fargate_spot ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 4
    }
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = var.use_fargate_spot ? 0 : 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.backend_sg_id]
    assign_public_ip = false
  }

  # Public ALB target group (for /api/*)
  load_balancer {
    target_group_arn = var.backend_target_group_arn
    container_name   = "backend"
    container_port   = 8080
  }

  # Internal ALB target group (for /internal/*)
  load_balancer {
    target_group_arn = var.backend_internal_tg_arn
    container_name   = "backend"
    container_port   = 8080
  }

  service_registries {
    registry_arn = aws_service_discovery_service.backend.arn
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# -----------------------------------------------------------------------------
# Gateway Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "gateway" {
  name            = "${var.project}-${var.environment}-gateway"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.gateway.arn
  desired_count   = var.gateway_desired_count

  dynamic "capacity_provider_strategy" {
    for_each = var.use_fargate_spot ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 4
    }
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = var.use_fargate_spot ? 0 : 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.gateway_sg_id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.gateway_target_group_arn != "" ? [1] : []
    content {
      target_group_arn = var.gateway_target_group_arn
      container_name   = "gateway"
      container_port   = 8443
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# -----------------------------------------------------------------------------
# Portal Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "portal" {
  name            = "${var.project}-${var.environment}-portal"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.portal.arn
  desired_count   = var.portal_desired_count

  dynamic "capacity_provider_strategy" {
    for_each = var.use_fargate_spot ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 4
    }
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = var.use_fargate_spot ? 0 : 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.portal_sg_id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.portal_target_group_arn != "" ? [1] : []
    content {
      target_group_arn = var.portal_target_group_arn
      container_name   = "portal"
      container_port   = 3002
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# -----------------------------------------------------------------------------
# Keycloak Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "keycloak" {
  name            = "${var.project}-${var.environment}-keycloak"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.keycloak.arn
  desired_count   = var.keycloak_desired_count

  dynamic "capacity_provider_strategy" {
    for_each = var.use_fargate_spot ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 4
    }
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = var.use_fargate_spot ? 0 : 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.keycloak_sg_id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.keycloak_target_group_arn != "" ? [1] : []
    content {
      target_group_arn = var.keycloak_target_group_arn
      container_name   = "keycloak"
      container_port   = 8080
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# -----------------------------------------------------------------------------
# Mailpit (email capture mode only) — catches all outbound email for QA.
# SMTP on 1025 (service discovery: mailpit.kazi.internal), UI/API on 8025
# behind the public ALB. Messages live in container memory/ephemeral storage —
# they do not survive task replacement, which is acceptable for QA capture.
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "mailpit" {
  count = local.email_capture ? 1 : 0

  family                   = "${var.project}-${var.environment}-mailpit"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.ecs_execution_role_arn

  container_definitions = jsonencode([
    {
      name      = "mailpit"
      image     = var.mailpit_image
      essential = true

      portMappings = [
        { containerPort = 1025, protocol = "tcp" },
        { containerPort = 8025, protocol = "tcp" },
      ]

      environment = [
        { name = "MP_MAX_MESSAGES", value = "5000" },
      ]

      secrets = [
        # user:password — enables basic auth on the UI and API (/livez and
        # /readyz stay unauthenticated for the ALB health check)
        { name = "MP_UI_AUTH", valueFrom = var.mailpit_ui_auth_arn },
      ]

      healthCheck = {
        command     = ["CMD", "/mailpit", "readyz"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.mailpit_log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_service_discovery_service" "mailpit" {
  count = local.email_capture ? 1 : 0

  name = "mailpit"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_service" "mailpit" {
  count = local.email_capture ? 1 : 0

  name            = "${var.project}-${var.environment}-mailpit"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mailpit[0].arn
  desired_count   = 1

  dynamic "capacity_provider_strategy" {
    for_each = var.use_fargate_spot ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 4
    }
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = var.use_fargate_spot ? 0 : 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.mailpit_sg_id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.mailpit_target_group_arn != "" ? [1] : []
    content {
      target_group_arn = var.mailpit_target_group_arn
      container_name   = "mailpit"
      container_port   = 8025
    }
  }

  service_registries {
    registry_arn = aws_service_discovery_service.mailpit[0].arn
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # Unlike the app services, Mailpit's task definition is fully Terraform-managed
  # (no CI/CD image pushes), so task_definition changes are NOT ignored.
}
