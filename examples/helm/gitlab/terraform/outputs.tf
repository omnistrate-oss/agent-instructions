# GitLab managed infrastructure — Terraform outputs
# Consumed in spec.yaml chartValues via {{ $gitlabManagedInfra.out.<key> }}
# (double-braces required when consuming terraform outputs in helmChartConfiguration.chartValues)

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port) — consumed as global.psql.host"
  value       = aws_db_instance.gitlab_postgres.address
  # Note: aws_db_instance.endpoint includes :<port>; use .address for host-only
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.gitlab_postgres.port
}

output "rds_db_name" {
  description = "PostgreSQL database name"
  value       = aws_db_instance.gitlab_postgres.db_name
}

output "redis_endpoint" {
  description = "ElastiCache Redis primary endpoint — consumed as global.redis.host"
  value       = aws_elasticache_replication_group.gitlab_redis.primary_endpoint_address
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = aws_elasticache_replication_group.gitlab_redis.port
}

output "s3_lfs_bucket" {
  description = "S3 bucket name for Git LFS — global.appConfig.lfs.bucket"
  value       = aws_s3_bucket.gitlab_buckets["lfs"].id
}

output "s3_artifacts_bucket" {
  description = "S3 bucket name for CI artifacts — global.appConfig.artifacts.bucket"
  value       = aws_s3_bucket.gitlab_buckets["artifacts"].id
}

output "s3_uploads_bucket" {
  description = "S3 bucket name for uploads — global.appConfig.uploads.bucket"
  value       = aws_s3_bucket.gitlab_buckets["uploads"].id
}

output "s3_packages_bucket" {
  description = "S3 bucket name for packages — global.appConfig.packages.bucket"
  value       = aws_s3_bucket.gitlab_buckets["packages"].id
}

output "s3_backups_bucket" {
  description = "S3 bucket name for backups — global.appConfig.backups.bucket"
  value       = aws_s3_bucket.gitlab_buckets["backups"].id
}

output "s3_tmp_bucket" {
  description = "S3 bucket name for temp — global.appConfig.backups.tmpBucket"
  value       = aws_s3_bucket.gitlab_buckets["tmp"].id
}
