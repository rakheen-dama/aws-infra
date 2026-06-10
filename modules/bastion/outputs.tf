output "instance_id" {
  description = "Bastion instance ID (target for aws ssm start-session)"
  value       = aws_instance.bastion.id
}

output "security_group_id" {
  description = "Bastion security group ID"
  value       = aws_security_group.bastion.id
}
