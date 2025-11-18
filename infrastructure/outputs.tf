output "alb_dns_name" {
  value = module.compute.alb_dns_name
}
output "app_url_https" {
  value = "https://${var.domain_name}"
}
output "rds_endpoint" {
  value = module.database.db_endpoint
}

output "ecs_cluster_name" {
  value       = module.compute.ecs_cluster_name
  description = "ECS cluster name"
}

output "ecs_service_name" {
  value       = module.compute.ecs_service_name
  description = "ECS service name"
}

output "log_group_name" {
  value       = module.compute.log_group_name
  description = "App CloudWatch Logs group"
}

output "migration_bucket_name" {
  value       = var.migration_bucket_name
  description = "S3 bucket used for migration dumps"
}

output "codebuild_project_name" {
  value       = aws_codebuild_project.restore.name
  description = "DB restore CodeBuild project"
}

output "codebuild_log_group" {
  value       = "/codebuild/${var.project_name}-db-restore"
  description = "CloudWatch Logs group for CodeBuild restore"
}

output "codebuild_smoke_log_group" {
  value = "/codebuild/${var.project_name}-db-smoke"
}
