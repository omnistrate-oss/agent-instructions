# Docker Compose Onboarding Reference

Complete reference for transforming Docker Compose applications to Omnistrate service definitions.

**Note**: This reference covers Docker Compose-based onboarding only. Other onboarding methods (Helm, Terraform, Kustomize, Kubernetes Operators) will have separate reference files when implemented.

## Table of Contents
1. [Prerequisites and Setup](#prerequisites-and-setup)
2. [Service Architecture Patterns](#service-architecture-patterns)
3. [API Parameters and Flow](#api-parameters-and-flow)
4. [Environment Variable Transformation](#environment-variable-transformation)
5. [Compute and Storage Configuration](#compute-and-storage-configuration)
6. [Capabilities and Features](#capabilities-and-features)
7. [Load Balancers](#load-balancers)
8. [ActionHooks](#actionhooks)
9. [Custom Metrics](#custom-metrics)
10. [Build and Deployment](#build-and-deployment)
11. [Debugging Workflow](#debugging-workflow)
12. [Troubleshooting](#troubleshooting)

## Prerequisites and Setup

### Cloud Accounts
```bash
# List available accounts
mcp__ctl__account_list

# Get account details for service plan
mcp__ctl__account_describe account-name="<account-name>"
```

Extract from account describe:
- **AWS**: AccountId, BootstrapRoleAccountArn
- **GCP**: ProjectId, ProjectNumber, ServiceAccountEmail
- **Azure**: SubscriptionId, TenantId

### System Parameters
```bash
# Get current system parameter schema
mcp__ctl__docs_system_parameters
```

Always verify `$sys.*` variable paths against current schema before use.

## Service Architecture Patterns

### Decision Tree
```
Count services in compose file:
  = 1 → Single service pattern
  ≥ 2 → Multi-service pattern (create root)
```

### Single Service Application
```yaml
version: "3.9"

x-omnistrate-service-plan:
  name: "service-plan"
  tenancyType: "OMNISTRATE_DEDICATED_TENANCY"
  deployment:
    hostedDeployment:
      AwsAccountId: "<from-account-describe>"
      AwsBootstrapRoleAccountArn: "<from-account-describe>"

services:
  database:
    image: vendor/database:latest
    x-omnistrate-mode-internal: false  # Single service = root
    x-omnistrate-api-params:
      - key: storageSize
        type: Float64
        defaultValue: "100"
    x-omnistrate-compute:
      instanceTypes:
        - cloudProvider: aws
          name: t3.xlarge
    x-omnistrate-capabilities:
      backupConfiguration:
        backupRetentionInDays: 7
```

### Multi-Service Application
```yaml
version: "3.9"

x-omnistrate-service-plan:
  name: "app-plan"
  tenancyType: "OMNISTRATE_DEDICATED_TENANCY"
  deployment:
    hostedDeployment:
      GcpProjectId: "<from-account-describe>"
      GcpProjectNumber: "<from-account-describe>"
      GcpServiceAccountEmail: "<from-account-describe>"

services:
  app:  # Synthetic root service
    image: omnistrate/noop
    x-omnistrate-mode-internal: false
    depends_on:
      - backend
      - database
      - cache
    x-omnistrate-api-params:
      - key: dbPassword
        type: Password
        export: false
        parameterDependencyMap:
          database: dbPassword
      - key: instanceType
        type: String
        defaultValue: "e2-standard-4"
        parameterDependencyMap:
          backend: instanceType
    x-omnistrate-capabilities:
      backupConfiguration:
        backupRetentionInDays: 7
        backupPeriodInHours: 24

  backend:
    image: myapp/backend:latest
    x-omnistrate-mode-internal: true
    depends_on:
      - database
      - cache
    x-omnistrate-api-params:
      - key: instanceType
        type: String
    x-omnistrate-compute:
      instanceTypes:
        - cloudProvider: gcp
          apiParam: instanceType
    environment:
      - DB_HOST="${database.sys.network.externalClusterEndpoint}"
      - CACHE_HOST="${cache.sys.network.externalClusterEndpoint}"
      - DB_PASSWORD="${var.dbPassword}"

  database:
    image: postgres:16
    x-omnistrate-mode-internal: true
    x-omnistrate-api-params:
      - key: dbPassword
        type: Password
    environment:
      - POSTGRES_PASSWORD=$var.dbPassword

  cache:
    image: redis:7
    x-omnistrate-mode-internal: true
```

## API Parameters and Flow

### Parameter Types
- `String` - Text values, instance types, names
- `Float64` - Numbers, replica counts, sizes
- `Boolean` - Feature flags
- `Password` - Sensitive values (set `export: false`)

### Simple Flow (Environment Variables)
**Use when**: Parameter only used in environment variables

```yaml
# Root service
services:
  app:
    x-omnistrate-api-params:
      - key: maxConnections
        type: Float64
        defaultValue: "100"
        min: 10
        max: 1000
        parameterDependencyMap:
          database: maxConnections

# Child service
  database:
    environment:
      - MAX_CONNECTIONS=$var.maxConnections
```

### Dual Definition (Infrastructure Configuration)
**Use when**: Parameter affects compute/storage/replicas

```yaml
# Root service
services:
  app:
    x-omnistrate-api-params:
      - key: nodeInstanceType
        type: String
        defaultValue: "e2-standard-4"
        options:
          - "e2-standard-2"
          - "e2-standard-4"
          - "e2-standard-8"
        parameterDependencyMap:
          backend: nodeInstanceType
      - key: numReplicas
        type: Float64
        defaultValue: "3"
        min: 1
        max: 10
        parameterDependencyMap:
          backend: numReplicas

# Child service (MUST redefine)
  backend:
    x-omnistrate-api-params:
      - key: nodeInstanceType
        type: String
      - key: numReplicas
        type: Float64
    x-omnistrate-compute:
      instanceTypes:
        - cloudProvider: gcp
          apiParam: nodeInstanceType
      replicaCountAPIParam: numReplicas
```

### Parameter with Options (Dropdown)
```yaml
x-omnistrate-api-params:
  - key: logLevel
    type: String
    defaultValue: "info"
    options:
      - "debug"
      - "info"
      - "warning"
      - "error"
    description: "Application logging level"
```

### Parameter with Bounds
```yaml
x-omnistrate-api-params:
  - key: cacheSize
    type: Float64
    defaultValue: "100"
    min: 10
    max: 1000
    description: "Cache size in MB"
```

## Environment Variable Transformation

### Variable Types

#### 1. API Parameters: `$var.<paramName>`
```yaml
environment:
  - DATABASE_PASSWORD=$var.dbPassword
  - MAX_CONNECTIONS=$var.maxConnections
  - LOG_LEVEL=$var.logLevel
```

#### 2. System Variables: `$sys.*`
**Always verify paths** using `mcp__ctl__docs_system_parameters`

Common patterns:
```yaml
environment:
  # Network endpoints
  - SELF_IP=$sys.network.node.externalEndpoint
  - CLUSTER_IP=$sys.network.externalClusterEndpoint

  # Deployment metadata
  - CLOUD_PROVIDER=$sys.deployment.cloudProvider
  - REGION=$sys.deploymentCell.region
  - INSTANCE_ID=$sys.id

  # Compute metadata
  - CPU_CORES=$sys.compute.node.cores
  - MEMORY_BYTES=$sys.compute.node.memory
```

#### 3. Cross-Service References: `$<service-name>.sys.*`
**Requires `depends_on` relationship**

```yaml
services:
  backend:
    depends_on:
      - database
      - cache
    environment:
      # Cross-service network references
      - DATABASE_HOST=$database.sys.network.externalClusterEndpoint
      - CACHE_ENDPOINT=$cache.sys.network.externalClusterEndpoint
      - DATABASE_PORT="5432"
```

### String Concatenation with {{ }}

**When concatenating** system parameters with ports, paths, or other text:

```yaml
environment:
  # ✅ Correct - Using {{ }} for concatenation
  - API_URL="{{ $sys.network.node.externalEndpoint }}:8000"
  - WEBHOOK_URL="{{ $sys.network.node.externalEndpoint }}/webhooks"
  - FRONTEND_URL="{{ $sys.network.node.externalEndpoint }}:3000/app"

  # Complex connection strings
  - DATABASE_URL="{{ $var.protocol }}://{{ $var.dbUser }}:{{ $var.dbPassword }}@{{ $database.sys.network.externalEndpoint }}:5432/{{ $var.dbName }}"

  # Multiple system parameters
  - DEPLOYMENT_TAG="{{ $sys.deployment.cloudProvider }}-{{ $sys.deploymentCell.region }}"

  # ❌ Incorrect - Will fail validation
  - API_URL=$sys.network.node.externalEndpoint:8000
  - DATABASE_URL=$var.protocol://$database.sys.network.externalEndpoint/db
```

**Rule**: Use `{{ }}` when combining variables with other text. Use `$var.*` or `$sys.*` alone when no concatenation.

## Compute and Storage Configuration

### Compute - Customer Choice
```yaml
x-omnistrate-compute:
  instanceTypes:
    - cloudProvider: gcp
      apiParam: nodeInstanceType
    - cloudProvider: aws
      apiParam: nodeInstanceType
  replicaCountAPIParam: numReplicas
```

### Compute - Fixed Configuration
```yaml
x-omnistrate-compute:
  instanceTypes:
    - cloudProvider: gcp
      name: e2-standard-4
    - cloudProvider: aws
      name: t3.xlarge
  replicaCount: 3
```

### Storage Configuration
```yaml
volumes:
  - source: ./data
    target: /data
    type: bind
    x-omnistrate-storage:
      gcp:
        instanceStorageType: GCP::PD_BALANCED
        instanceStorageSizeGi: 100
      aws:
        instanceStorageType: AWS::EBS_GP3
        instanceStorageSizeGi: 100
      azure:
        instanceStorageType: Azure::PREMIUM_LRS
        instanceStorageSizeGi: 100
```

**Storage types**:
- **GCP**: `GCP::PD_BALANCED`, `GCP::PD_SSD`, `GCP::PD_STANDARD`
- **AWS**: `AWS::EBS_GP3`, `AWS::EBS_GP2`, `AWS::EBS_IO1`
- **Azure**: `Azure::STANDARD_LRS`, `Azure::PREMIUM_LRS`

### Parameterized Storage
```yaml
# API parameter
x-omnistrate-api-params:
  - key: storageSize
    type: Float64
    defaultValue: "100"
    min: 50
    max: 1000

# Volume configuration
volumes:
  - source: ./data
    target: /data
    type: bind
    x-omnistrate-storage:
      gcp:
        instanceStorageType: GCP::PD_BALANCED
        instanceStorageSizeGi: $var.storageSize
```

## Capabilities and Features

### Backup Configuration
**Only on root service** (x-omnistrate-mode-internal: false)

```yaml
x-omnistrate-capabilities:
  backupConfiguration:
    backupRetentionInDays: 7
    backupPeriodInHours: 24
```

### Multi-Zone Deployment
```yaml
x-omnistrate-capabilities:
  enableMultiZone: true
```

### Endpoint Per Replica
```yaml
x-omnistrate-capabilities:
  enableEndpointPerReplica: true
```

### Autoscaling
```yaml
x-omnistrate-capabilities:
  autoscalingConfig:
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilization: 75
```

## Load Balancers

### Decision: When to Add
**Add when**:
- Service has `replicaCount > 1` OR autoscaling enabled
- Service is externally accessible
- NOT internal-only services
- NOT omnistrate/noop services

### TCP Load Balancer (Databases, Caches)
```yaml
x-omnistrate-load-balancer:
  tcp:
    - name: "Database Load Balancer"
      description: "Load balancer for PostgreSQL cluster"
      ports:
        - associatedResourceKeys:
            - postgres-primary
            - postgres-replica
          ingressPort: 5432
          backendPort: 5432
```

### HTTP Load Balancer (Web Services, APIs)
```yaml
x-omnistrate-load-balancer:
  http:
    - name: "API Load Balancer"
      description: "Load balancer for API service"
      ports:
        - associatedResourceKeys:
            - api
          ingressPort: 443
          backendPort: 8080
      healthCheck:
        path: /health
        port: 8080
        intervalSeconds: 30
        timeoutSeconds: 5
```

### Multiple Load Balancers
```yaml
x-omnistrate-load-balancer:
  tcp:
    - name: "Cache LB"
      ports:
        - associatedResourceKeys: [redis]
          ingressPort: 6379
          backendPort: 6379
  http:
    - name: "Web LB"
      ports:
        - associatedResourceKeys: [web]
          ingressPort: 80
          backendPort: 8080
      healthCheck:
        path: /
        port: 8080
```

## ActionHooks

### Health Check Hook
```yaml
x-omnistrate-actionhooks:
  - scope: NODE
    type: HEALTH_CHECK
    command: |
      #!/bin/bash
      curl -f http://localhost:8080/health || exit 1
      exit 0
    timeout: 30
    retries: 3
```

### Post-Start Hook
```yaml
x-omnistrate-actionhooks:
  - scope: NODE
    type: POST_START
    command: |
      #!/bin/bash
      /app/init-db.sh
      /app/load-initial-data.sh
      exit 0
    timeout: 300
```

### Pre-Stop Hook (Graceful Shutdown)
```yaml
x-omnistrate-actionhooks:
  - scope: NODE
    type: PRE_STOP
    command: |
      #!/bin/bash
      /app/drain-connections.sh
      /app/graceful-shutdown.sh
      exit 0
    timeout: 120
```

### REMOVE Hook (Clustered Services)
**Use for**: Primary/replica failover, leader election, state transfer

```yaml
x-omnistrate-actionhooks:
  - scope: NODE
    type: REMOVE
    commandTemplate: |
      #!/bin/bash
      # Check if this is the primary node
      role=$(curl -s http://localhost:8080/role)
      if [ "$role" == "primary" ]; then
          # Trigger failover before removal
          curl -X POST http://$COORDINATOR_HOST/failover
          sleep 10
      fi
      exit 0
    timeout: 120
```

**Key difference**:
- `command`: Static script, same for all nodes
- `commandTemplate`: Dynamic script with environment variable substitution

## Custom Metrics

### Pattern: YAML Anchors for Reusability
```yaml
# Define once at top level
x-appMetrics: &appMetrics
  prometheusEndpoint: "http://localhost:9090/metrics"
  metrics:
    http_requests_total:
      "Total HTTP Requests":
        aggregationFunction: sum
        description: "Total number of HTTP requests"
    http_request_duration_seconds_bucket:
      "Request Duration Bucket":
        aggregationFunction: sum
        description: "Request duration distribution"
    active_connections:
      "Active Connections":
        aggregationFunction: avg
        description: "Current active connections"
    memory_used_bytes:
      "Memory Used":
        aggregationFunction: max
        description: "Memory usage in bytes"

# Use in services
services:
  backend:
    x-omnistrate-integrations:
      - x-appMetrics: *appMetrics
```

### Aggregation Functions
- `sum` - Throughput, total requests, cumulative counters
- `avg` - Latency, utilization, resource usage
- `max` - Peak values, max memory, max connections
- `min` - Minimum values (rarely used)
- `count` - Occurrence counts

## Build and Deployment

### Build Service
```bash
mcp__ctl__build_compose \
  file="docker-compose-omnistrate.yaml" \
  service_name="my-service" \
  description="Service description"
```

### List Service Plans
```bash
mcp__ctl__service_plan_list service_name="my-service"
mcp__ctl__service_plan_describe service_name="my-service" plan_name="<plan>"
```

### Create Instance
```bash
mcp__ctl__instance_create \
  service_name="my-service" \
  plan_name="default" \
  environment="prod" \
  cloud_provider="gcp" \
  region="us-central1" \
  instance_name="customer-instance-1"
```

### Monitor Deployment
```bash
# Check status
mcp__ctl__instance_describe \
  service_name="my-service" \
  instance_id="<id>" \
  deployment_status=true

# List workflows
mcp__ctl__workflow_list \
  service_name="my-service" \
  instance_id="<id>"

# Get workflow events
mcp__ctl__workflow_events \
  service_name="my-service" \
  workflow_id="<id>"
```

## Debugging Workflow

### Systematic Approach
Refer to `../omnistrate-sre/SKILL.md` for complete debugging workflow.

**Quick reference**:
1. Get deployment status with `--deployment-status` flag
2. Identify failed workflows
3. Analyze workflow events (summary first, then detail)
4. Check application logs with kubectl if probe failures
5. Verify Helm releases for Helm-based resources
6. Fix issues in compose spec
7. Rebuild and redeploy
8. **Iterate until RUNNING**

### Common Issues

#### Instance Type Unavailable
```
Error: VM allocation failed - instance type not available in zone
Fix: Change instance type or select different region
```

#### Volume Creation Failed
```
Error: PersistentVolumeClaim stuck in Pending
Fix: Check storage type compatibility, reduce size if quota exceeded
```

#### Probe Failures
```
Error: Readiness probe failed: HTTP 503
Fix: Check application logs, verify dependencies, check env vars
```

#### Environment Variable Errors
```
Error: undefined variable $var.dbPassword
Fix: Add parameter to x-omnistrate-api-params on root service
```

#### Cross-Service Reference Failed
```
Error: undefined variable $database.sys.network.externalEndpoint
Fix: Add depends_on: [database] to service
```

### Iteration Loop
```
1. Deploy instance
2. Monitor status
3. If FAILED:
   a. Analyze workflow events
   b. Identify root cause
   c. Fix compose spec
   d. Rebuild service
   e. Delete failed instance
   f. Deploy again
4. Repeat until RUNNING and healthy
```

## Troubleshooting

### Validation Errors
```bash
# Get JSON schema for validation
mcp__ctl__docs_compose_spec_search \
  query="x-omnistrate-compute" \
  json_schema_only=true
```

### Parameter Not Found
```
Error: parameter 'instanceType' not found
Fix: Ensure parameter defined in x-omnistrate-api-params
```

### Cloud Account Issues
```
Error: invalid cloud account
Fix: Re-run mcp__ctl__account_describe and copy exact values
```

### Storage Mount Failed
```
Error: volume mount failed
Fix: Verify storage type valid for cloud/instance type
```

### Build Failures
Search documentation for extension causing error:
```bash
mcp__ctl__docs_compose_spec_search query="<problematic-extension>"
```

## Integration Configuration

### Native Logging and Metrics
```yaml
x-omnistrate-integrations:
  - omnistrateLogging: {}
  - omnistrateMetrics: {}
```

### Advanced Integration
```yaml
x-internal-integrations:
  logs:
    provider: native
  metrics:
    provider: native
```

## Complete Example

See COMPOSE-ONBOARDING.md for complete multi-service example with:
- Synthetic root service
- API parameters with dual definition
- Cross-service references
- Compute/storage configuration
- Backup capabilities
- Load balancers
- Custom metrics
- ActionHooks
