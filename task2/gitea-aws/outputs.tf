# =========================
# Terraform Outputs
# =========================

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "rds_endpoint" {
  description = "Endpoint address of the PostgreSQL RDS instance"
  value       = aws_db_instance.main.address
}

output "efs_id" {
  description = "ID of the EFS file system used for persistent storage"
  value       = aws_efs_file_system.gitea.id
}

output "efs_dns_name" {
  description = "DNS name of the EFS mount target (used by EC2 instances)"
  value       = aws_efs_file_system.gitea.dns_name
}

output "asg_name" {
  description = "Auto Scaling Group name for the application servers"
  value       = aws_autoscaling_group.app.name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret storing DB credentials"
  value       = aws_secretsmanager_secret.db_secret.arn
}

output "aws_region" {
  description = "AWS region in which the stack is deployed"
  value       = var.aws_region
}
