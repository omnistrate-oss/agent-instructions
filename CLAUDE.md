# Claude Code Instructions

This file configures Claude Code with specialized skills for working with the Omnistrate platform.

## Available Skills

### Onboarding Services to Omnistrate
**Location**: `skills/omnistrate-fde/`

Guide users through onboarding applications onto the Omnistrate platform. Currently supports Docker Compose-based services with full deployment lifecycle management.

**When to use**:
- Onboarding applications to Omnistrate platform
- Creating SaaS offerings with multi-tenant infrastructure
- Transforming Docker Compose files into Omnistrate service definitions
- Setting up customer-facing service catalogs

**Supported methods**:
- Docker Compose (fully supported)
- Helm, Terraform, Kustomize, Kubernetes Operators (planned - direct users to https://docs.omnistrate.com/getting-started/overview/)

**Key capabilities**:
- Compose spec transformation with validation
- API parameter configuration and flow patterns
- Compute and storage resource setup
- Iterative debugging until instances are RUNNING
- Multi-service architecture with synthetic root patterns

### Debugging Omnistrate Deployments
**Location**: `skills/omnistrate-sre/`

Systematically debug failed Omnistrate instance deployments using a progressive workflow that identifies root causes efficiently while avoiding token limits.

**When to use**:
- Instance deployments showing FAILED or DEPLOYING status
- Resources with unhealthy pod statuses or deployment errors
- Startup/readiness probe failures (HTTP 503, timeouts)
- Helm releases with unclear deployment states
- Need to identify root cause of deployment failures

**Key capabilities**:
- Progressive debugging workflow (status → workflows → events → logs)
- Pod-level investigation with kubectl
- Helm-specific verification
- Common failure pattern recognition
- Infrastructure and application-level analysis

