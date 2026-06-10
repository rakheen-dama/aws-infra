output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions role (set as AWS_ROLE_ARN secret in the repos)"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = local.oidc_provider_arn
}
