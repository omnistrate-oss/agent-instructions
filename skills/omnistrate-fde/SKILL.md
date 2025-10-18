---
name: Onboarding Services to Omnistrate
description: Guide users through onboarding applications onto the Omnistrate platform. Currently supports Docker Compose-based services with full deployment lifecycle management. Future support planned for Helm charts, Terraform modules, Kustomize configurations, and Kubernetes operators. Handles service transformation, API parameter configuration, compute/storage setup, and iterative debugging until instances are running.
---

# Onboarding Services to Omnistrate

## When to Use This Skill
- Onboarding applications to Omnistrate platform
- Creating SaaS offerings with multi-tenant infrastructure
- Setting up customer-facing service catalogs
- Building managed services with automated deployment
- Transforming existing applications for cloud delivery

## Supported Onboarding Methods

### Currently Supported
**Docker Compose** - Transform compose files into Omnistrate service definitions
- Use for: Containerized applications with compose specs
- Status: Fully supported with complete workflow

### Future Support (Not Yet Implemented)
- **Helm Charts** - Deploy Kubernetes applications via Helm
- **Terraform Modules** - Infrastructure-as-code based services
- **Kustomize** - Kubernetes configuration management
- **Kubernetes Operators** - Operator-based service management

**Note**: When users ask about Helm, Terraform, Kustomize, or Operators, inform them these are not yet supported by this skill and direct them to https://docs.omnistrate.com/getting-started/overview/ for documentation on these methods.

## Quick Decision Guide

### 1. Check Input Format
- **Docker Compose file** → Continue with this skill (full support)
- **Helm/Terraform/Kustomize/Operators** → Not supported, see https://docs.omnistrate.com/getting-started/overview/

### 2. Determine Architecture Pattern
Count services in your compose file:
- **1 service** → Single service pattern (simpler, service is root)
- **2+ services** → Multi-service pattern (requires synthetic root service)

### 3. What is a Synthetic Root Service?
For multi-service applications, Omnistrate requires one "parent" service to coordinate all others. This parent:
- Uses special `omnistrate/noop` image (no actual workload)
- Serves as entry point for all API parameters
- Holds backup configuration
- Orchestrates children via `depends_on` relationships

## Docker Compose Workflow

**Quick Start**: Verify cloud account → Create `-omnistrate.yaml` → Add service plan → Transform services → Build → Deploy → Debug until RUNNING

### 1. Preparation
**Analyze compose file structure** (Docker Compose only):
- Count services (determines single vs multi-service pattern)
- Identify service dependencies (depends_on chains)
- Map environment variables for parameterization
- Determine stateful services (volumes, databases)

**Verify cloud accounts**:
```bash
mcp__ctl__account_list
mcp__ctl__account_describe account-name="<name>"
```
Extract account IDs, bootstrap roles, project IDs for service plan configuration.

### 2. Transformation
**Never modify original compose file** - create new `-omnistrate.yaml` file

**Search documentation before every extension**:
```bash
mcp__ctl__docs_compose_spec_search query="<extension-name>"
mcp__ctl__docs_system_parameters  # For $sys.* variable paths
```

**Service architecture decision**:
- Single service (count = 1): Mark service with `x-omnistrate-mode-internal: false`
- Multi-service (count ≥ 2): Create synthetic root service using `omnistrate/noop` image

**Key transformations**:
1. Add service plan with real cloud account values
2. Create/configure root service (multi-service apps)
3. Mark child services as internal (`x-omnistrate-mode-internal: true`)
4. Define API parameters on root service
5. Transform environment variables to use `$var.*` and `$sys.*` references
6. Configure compute resources per service
7. Transform volumes to `x-omnistrate-storage` definitions
8. Add capabilities (backups, autoscaling, multi-zone)
9. Configure load balancers (only for replicas > 1)
10. Add integrations (logging, metrics)

### 3. Build and Deploy
```bash
mcp__ctl__build_compose file="docker-compose-omnistrate.yaml" service_name="<name>"
mcp__ctl__service_plan_list service_name="<name>"
mcp__ctl__instance_create service_name="<name>" plan_name="<plan>" ...
```

### 4. Debug Until RUNNING
**Iterate until instance status is RUNNING and all resources healthy**:
```bash
mcp__ctl__instance_describe service_name="<name>" instance_id="<id>" deployment_status=true
mcp__ctl__workflow_list service_name="<name>" instance_id="<id>"
mcp__ctl__workflow_events service_name="<name>" workflow_id="<id>"
```

Refer to `../omnistrate-sre/SKILL.md` for systematic debugging approach.

**Common fixes**:
- Instance type unavailable → change type or region
- Volume creation failed → adjust storage type/size
- Probe failures → check logs with kubectl, fix app dependencies/env vars
- Environment variable errors → verify parameter definitions and system variable paths

**Do not stop at first failure** - most deployments require 2-3 iterations.

## Critical Rules

### Documentation Verification
- **Always search docs** before using any `x-omnistrate-*` extension
- **Verify system parameters** using `mcp__ctl__docs_system_parameters` before using `$sys.*` variables
- **Never hallucinate** syntax - if doc search returns no results, skip the feature
- **Skip when uncertain** - working basic service > broken advanced service

### Parameter Flow Patterns

**Simple flow** (root → child for env vars):
```yaml
# Root service
x-omnistrate-api-params:
  - key: cacheSize
    parameterDependencyMap:
      redis: cacheSize

# Child service
environment:
  - MAX_MEMORY=$var.cacheSize
```

**Dual definition** (required for compute/storage):
```yaml
# Root service
x-omnistrate-api-params:
  - key: instanceType
    parameterDependencyMap:
      backend: instanceType

# Child service (MUST redefine)
x-omnistrate-api-params:
  - key: instanceType
x-omnistrate-compute:
  instanceTypes:
    - cloudProvider: gcp
      apiParam: instanceType
```

### String Concatenation
Use `{{ }}` syntax when concatenating system parameters:
```yaml
environment:
  # ✅ Correct
  - API_URL="{{ $sys.network.node.externalEndpoint }}:8000"
  - DB_URL="{{ $var.protocol }}://{{ $postgres.sys.network.externalEndpoint }}/{{ $var.dbName }}"

  # ❌ Incorrect
  - API_URL=$sys.network.node.externalEndpoint:8000
```

### Cross-Service References
**Requires** `depends_on` relationship:
```yaml
services:
  backend:
    depends_on:
      - database  # Required
    environment:
      - DB_HOST="${database.sys.network.externalClusterEndpoint}"
```

### Backup Configuration
**Only on services with** `x-omnistrate-mode-internal: false`:
- Multi-service: Add to root service only
- Single-service: Add to the single service (if stateful)
- Never add to services with `x-omnistrate-mode-internal: true`

### Load Balancers
**Only add when**:
- Service has replicas > 1 OR autoscaling enabled
- Service is externally accessible
- NOT for omnistrate/noop services

## Architecture Patterns

### Single Service
```yaml
services:
  web:
    x-omnistrate-mode-internal: false  # Root service
    x-omnistrate-api-params: [...]
    x-omnistrate-compute: [...]
```

### Multi-Service
```yaml
services:
  app:  # Synthetic root (orchestrator)
    image: omnistrate/noop  # Special Omnistrate image (no workload)
    x-omnistrate-mode-internal: false
    depends_on: [web, database]
    x-omnistrate-api-params: [...]
    x-omnistrate-capabilities:
      backupConfiguration: [...]  # Only on root

  web:
    x-omnistrate-mode-internal: true

  database:
    x-omnistrate-mode-internal: true
```

## Success Criteria
- ✅ Build succeeds without validation errors
- ✅ **Instance reaches RUNNING status**
- ✅ **All resources healthy (not FAILED)**
- ✅ All health checks pass
- ✅ Parameters work as expected
- ✅ Multiple instances can run concurrently
- ✅ **Completed at least one deploy-debug-fix cycle**
- ✅ All transformations based on verified documentation
- ✅ Skipped features documented with reasons


## Reference

### Docker Compose
See COMPOSE_ONBOARDING_REFERENCE.md for:
- Complete step-by-step transformation guide
- Detailed extension syntax examples
- Environment variable interpolation patterns
- Storage configuration by cloud provider
- ActionHooks examples
- Custom metrics configuration
- Troubleshooting guide with common errors

### Other Methods
When additional onboarding methods are implemented, their reference documentation will be linked here.
