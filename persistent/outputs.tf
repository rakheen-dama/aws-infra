output "github_actions_role_arn" {
  description = "Set as the AWS_ROLE_ARN secret in all three repos"
  value       = module.github_oidc.github_actions_role_arn
}

output "ecr_repository_urls" {
  description = "ECR repository URLs (empty map when manage_shared = false)"
  value       = var.manage_shared ? module.ecr[0].ecr_repository_urls : {}
}

output "s3_bucket_name" {
  description = "App document bucket name"
  value       = module.s3.bucket_name
}

output "secret_arns" {
  description = "Map of secret name to ARN"
  value       = module.secrets.secret_arns
}
