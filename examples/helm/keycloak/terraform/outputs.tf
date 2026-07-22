# outputs.tf — Keycloak RDS PostgreSQL
# These outputs are captured by Omnistrate after terraform apply and made available
# to dependent services via {{ $keycloakDb.out.<key> }} in spec.yaml chartValues.
# (see TERRAFORM_KUSTOMIZE_REFERENCE.md § Outputs)

output "db_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port). Used by keycloak service via {{ $keycloakDb.out.db_endpoint }}."
  value       = aws_db_instance.keycloak_postgres.endpoint
}

output "db_host" {
  description = "RDS PostgreSQL hostname only (without port)."
  value       = aws_db_instance.keycloak_postgres.address
}

output "db_port" {
  description = "RDS PostgreSQL port."
  value       = aws_db_instance.keycloak_postgres.port
}

output "db_name" {
  description = "Database name."
  value       = aws_db_instance.keycloak_postgres.db_name
}
