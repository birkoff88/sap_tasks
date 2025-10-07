# task2/gitea-aws/outputs.tf

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "rds_endpoint" {
  description = "Endpoint address of the PostgreSQL RDS instance"
  value       = aws_db_instance.postgres.address
}

output "efs_id" {
  description = "ID of the EFS file system used for persistent storage"
  value       = aws_efs_file_system.gitea.id
}

output "efs_dns_name" {
  description = "Regional DNS name of the EFS file system"
  value       = aws_efs_file_system.gitea.dns_name
}

output "aws_region" {
  description = "AWS region where the stack is deployed"
  value       = var.aws_region
}
