variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "kazi"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC to place the bastion in"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID for the bastion instance"
  type        = string
}

variable "rds_sg_id" {
  description = "RDS security group ID (gains a 5432 ingress rule from the bastion)"
  type        = string
}

variable "redis_sg_id" {
  description = "Redis security group ID (gains a 6379 ingress rule from the bastion)"
  type        = string
}

variable "instance_type" {
  description = "Bastion instance type"
  type        = string
  default     = "t4g.nano"
}
