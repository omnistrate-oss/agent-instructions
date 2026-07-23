# GitLab managed infrastructure — RDS PostgreSQL + ElastiCache Redis + S3 buckets
# Follows the Omnistrate managed-service module pattern for chart dependencies
# (see TERRAFORM_KUSTOMIZE_REFERENCE.md § Managed-service modules for chart dependencies).
#
# Omnistrate manages state automatically; do NOT author a backend block.
# ${{ $sys.* }} references are rendered by Omnistrate at plan time.

provider "aws" {
  region = "{{ $sys.deploymentCell.region }}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Variables (set via variablesValuesFileOverride in spec.yaml)
# ──────────────────────────────────────────────────────────────────────────────

variable "vpc_id" {
  description = "VPC ID (from Omnistrate deployment cell)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "resource_prefix" {
  description = "Unique prefix for all resource names (includes $sys.id)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from Omnistrate deployment cell"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from Omnistrate deployment cell"
  type        = list(string)
}

# ──────────────────────────────────────────────────────────────────────────────
# Security Groups
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "rds_sg" {
  name        = "${var.resource_prefix}-rds-sg"
  description = "Security group for GitLab RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]   # tighten to VPC CIDR for production
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resource_prefix}-rds-sg"
  }
}

resource "aws_security_group" "redis_sg" {
  name        = "${var.resource_prefix}-redis-sg"
  description = "Security group for GitLab ElastiCache Redis"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.resource_prefix}-redis-sg"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# RDS PostgreSQL (GitLab database)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "gitlab_db_subnet" {
  name        = "${var.resource_prefix}-db-subnet"
  description = "GitLab RDS subnet group"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.resource_prefix}-db-subnet"
  }
}

resource "aws_db_instance" "gitlab_postgres" {
  identifier              = "${var.resource_prefix}-postgres"
  engine                  = "postgres"
  engine_version          = "14.17"
  instance_class          = "db.t3.large"    # TODO-GAP: thread $var.dbInstanceClass from spec apiParameters via variablesValuesFileOverride
  allocated_storage       = 100
  max_allocated_storage   = 1000             # auto-scaling storage
  db_name                 = "gitlabhq_production"
  username                = "gitlab"
  password                = "ChangeMe123!"   # manage via $secret.GITLAB_DB_PASSWORD in production
  db_subnet_group_name    = aws_db_subnet_group.gitlab_db_subnet.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  parameter_group_name    = "default.postgres14"
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  multi_az                = true             # production HA
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.resource_prefix}-postgres-final"
  storage_encrypted       = true
  deletion_protection     = true

  tags = {
    Name = "${var.resource_prefix}-postgres"
  }

  depends_on = [
    aws_db_subnet_group.gitlab_db_subnet,
    aws_security_group.rds_sg,
  ]
}

# ──────────────────────────────────────────────────────────────────────────────
# ElastiCache Redis (GitLab session cache, background jobs)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "gitlab_redis_subnet" {
  name        = "${var.resource_prefix}-redis-subnet"
  description = "GitLab ElastiCache subnet group"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.resource_prefix}-redis-subnet"
  }
}

resource "aws_elasticache_replication_group" "gitlab_redis" {
  replication_group_id       = "${var.resource_prefix}-redis"
  description                = "GitLab Redis replication group"
  node_type                  = "cache.t3.medium"  # TODO-GAP: thread $var.redisNodeType
  port                       = 6379
  parameter_group_name       = "default.redis7"
  engine_version             = "7.0"
  automatic_failover_enabled = true
  num_cache_clusters         = 2                  # primary + 1 replica for HA
  subnet_group_name          = aws_elasticache_subnet_group.gitlab_redis_subnet.name
  security_group_ids         = [aws_security_group.redis_sg.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false              # set true and configure auth if AUTH required

  tags = {
    Name = "${var.resource_prefix}-redis"
  }

  depends_on = [
    aws_elasticache_subnet_group.gitlab_redis_subnet,
    aws_security_group.redis_sg,
  ]
}

# ──────────────────────────────────────────────────────────────────────────────
# S3 Buckets — GitLab requires multiple buckets
# Ref: global.appConfig.{lfs,artifacts,uploads,packages,backups,dependencyProxy}
# ──────────────────────────────────────────────────────────────────────────────

locals {
  buckets = {
    lfs       = "${var.resource_prefix}-git-lfs"
    artifacts = "${var.resource_prefix}-gitlab-artifacts"
    uploads   = "${var.resource_prefix}-gitlab-uploads"
    packages  = "${var.resource_prefix}-gitlab-packages"
    backups   = "${var.resource_prefix}-gitlab-backups"
    tmp       = "${var.resource_prefix}-gitlab-tmp"
  }
}

resource "aws_s3_bucket" "gitlab_buckets" {
  for_each      = local.buckets
  bucket        = each.value
  force_destroy = false   # protect data; set true only in dev

  tags = {
    Name    = each.value
    Purpose = "gitlab-${each.key}"
  }
}

resource "aws_s3_bucket_versioning" "gitlab_buckets" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.gitlab_buckets[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab_buckets" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.gitlab_buckets[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}
