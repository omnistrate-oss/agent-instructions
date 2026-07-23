# RDS PostgreSQL for Keycloak — Omnistrate managed-service module
# Follows the Omnistrate managed-service module pattern for chart dependencies
# (see TERRAFORM_KUSTOMIZE_REFERENCE.md § Managed-service modules for chart dependencies)
# All {{ $sys.* }} and {{ $var.* }} are rendered by Omnistrate at deploy time.

provider "aws" {
  region = "{{ $sys.deploymentCell.region }}"
}

# ── Variables ─────────────────────────────────────────────────────────────────
# These are injected via variablesValuesFileOverride in spec.yaml.
# Do NOT add a backend block — Omnistrate manages state automatically.

variable "vpc_id" {
  description = "VPC ID of the deployment cell (set by Omnistrate via variablesValuesFileOverride)"
  type        = string
}

variable "region" {
  description = "AWS region (set by Omnistrate via variablesValuesFileOverride)"
  type        = string
  default     = "{{ $sys.deploymentCell.region }}"
}

variable "db_password" {
  description = "Password for the Keycloak database user"
  type        = string
  sensitive   = true
}

variable "resource_id" {
  description = "Unique Omnistrate resource/instance ID — used for naming to avoid collisions"
  type        = string
}

# ── Security group ─────────────────────────────────────────────────────────────

resource "aws_security_group" "keycloak_rds_sg" {
  name        = "keycloak-rds-sg-{{ $sys.id }}"
  description = "Security group for Keycloak RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from within the VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["{{ $sys.deploymentCell.cidrRange }}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "keycloak-rds-sg-{{ $sys.id }}"
  }
}

# ── DB subnet group (private subnets) ──────────────────────────────────────────

resource "aws_db_subnet_group" "keycloak_subnet_group" {
  name        = "keycloak-sng-{{ $sys.id }}"
  description = "Subnet group for Keycloak RDS"
  subnet_ids  = [
    "{{ $sys.deploymentCell.privateSubnetIDs[0].id }}",
    "{{ $sys.deploymentCell.privateSubnetIDs[1].id }}"
  ]

  tags = {
    Name = "keycloak-sng-{{ $sys.id }}"
  }
}

# ── RDS PostgreSQL instance ────────────────────────────────────────────────────

resource "aws_db_instance" "keycloak_postgres" {
  identifier              = "keycloak-db-{{ $sys.id }}"
  engine                  = "postgres"
  engine_version          = "15.7"
  instance_class          = "db.t3.medium"
  allocated_storage       = 20
  storage_type            = "gp3"
  db_name                 = "keycloak"
  username                = "keycloak_user"
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.keycloak_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.keycloak_rds_sg.id]
  parameter_group_name    = "default.postgres15"
  skip_final_snapshot     = true
  publicly_accessible     = false
  backup_retention_period = 7

  tags = {
    Name = "keycloak-db-{{ $sys.id }}"
  }

  depends_on = [
    aws_security_group.keycloak_rds_sg,
    aws_db_subnet_group.keycloak_subnet_group
  ]
}
