# Docker Compose Onboarding Reference

Complete reference for transforming Docker Compose applications to Omnistrate service definitions.

**Note**: This reference covers Docker Compose-based onboarding only. Other onboarding methods (Helm, Terraform, Kustomize, Kubernetes Operators) will have separate reference files when implemented.

## Table of Contents
1. [Prerequisites and Setup](#prerequisites-and-setup)
2. [Deployment Model](#deployment-model)
3. [Service Architecture Patterns](#service-architecture-patterns)
4. [Phased Parameterization Strategy](#phased-parameterization-strategy)
5. [Image Registry Authentication](#image-registry-authentication)
6. [API Parameters and Flow](#api-parameters-and-flow)
7. [Environment Variable Transformation](#environment-variable-transformation)
8. [Compute and Storage Configuration](#compute-and-storage-configuration)
9. [Capabilities and Features](#capabilities-and-features)
10. [Load Balancers](#load-balancers)
11. [ActionHooks](#actionhooks)
12. [Custom Metrics](#custom-metrics)
13. [Build and Deployment](#build-and-deployment)
14. [Debugging Workflow](#debugging-workflow)
15. [Troubleshooting](#troubleshooting)

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

## Deployment Model

Model selection, account setup, BYOC/BYOC-K8s/air-gapped flows: see `DEPLOYMENT_MODELS_REFERENCE.md`.

**Default**: Always use `hostedDeployment` (your SaaS service runs in your provider account). Only switch to `byoaDeployment` if you want to offer BYOC to customers, or `onPremDeployment` for on-premise.

Compose spec syntax (lowerCamel fields — see `DEPLOYMENT_MODELS_REFERENCE.md` for the full field reference and casing rules):

```yaml
x-omnistrate-service-plan:
  name: "my-service"
  tenancyType: "OMNISTRATE_DEDICATED_TENANCY"
  deployment:
    hostedDeployment:
      awsAccountId: "<AWS_ACCOUNT_ID>"
      awsBootstrapRoleAccountArn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
      gcpProjectId: "<GCP_PROJECT_ID>"
      gcpProjectNumber: "<GCP_PROJECT_NUMBER>"
      gcpServiceAccountEmail: "<GCP_SA_EMAIL>"
      azureSubscriptionId: "<AZURE_SUBSCRIPTION_ID>"
      azureTenantId: "<AZURE_TENANT_ID>"
```

Configure only the cloud providers you plan to support. Obtain values from `mcp__ctl__account_describe`.

## Service Architecture Patterns

### Decision Tree
```
Count services in compose file:
  = 1 → Single service pattern
  ≥ 2 → Multi-service pattern (create root)
```

### Single Service Application

One service → the service itself is the root (`x-omnistrate-mode-internal: false`). No synthetic root needed.

```yaml
version: "3.9"

x-omnistrate-service-plan:
  name: "service-plan"
  tenancyType: "OMNISTRATE_DEDICATED_TENANCY"
  deployment:
    hostedDeployment:   # See Deployment Model section and DEPLOYMENT_MODELS_REFERENCE.md
      awsAccountId: "<from-account-describe>"
      awsBootstrapRoleAccountArn: "<from-account-describe>"

services:
  database:
    image: vendor/database:latest
    x-omnistrate-mode-internal: false  # Single service = root
    x-omnistrate-compute:
      instanceTypes:
        - cloudProvider: aws
          name: t3.xlarge
    x-omnistrate-capabilities:
      backupConfiguration:
        backupRetentionInDays: 7
```

### Multi-Service Application

Two or more services → create a synthetic root using `omnistrate/noop` (no actual workload). The root:
- Uses `image: omnistrate/noop`
- Is the only service with `x-omnistrate-mode-internal: false`
- Holds all top-level API parameters and backup configuration
- Lists all child services in `depends_on`

```yaml
version: "3.9"

x-omnistrate-service-plan:
  name: "app-plan"
  tenancyType: "OMNISTRATE_DEDICATED_TENANCY"
  deployment:
    hostedDeployment:   # See Deployment Model section and DEPLOYMENT_MODELS_REFERENCE.md
      gcpProjectId: "<from-account-describe>"
      gcpProjectNumber: "<from-account-describe>"
      gcpServiceAccountEmail: "<from-account-describe>"

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
        snapshotBeforeDeletion: true  # Take final snapshot before deletion

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

## Phased Parameterization Strategy

**CRITICAL RULE**: Always start with ZERO parameterization. Only add API parameters AFTER initial deployment succeeds AND user explicitly requests customization.

### Phase 1: Initial Build (ZERO parameterization — get a working deployment first)

- NO `x-omnistrate-api-params` on any service
- NO `$var.*` references in environment variables
- NO `{{ }}` concatenations
- All passwords: Hardcoded defaults, e.g. `"ChangeMe123!"`
- All replica counts: Fixed numbers, e.g. `replicaCount: 3`
- All storage sizes: Hardcoded numbers, e.g. `instanceStorageSizeGi: 100`
- All environment variables: Hardcoded values
- No autoscaling (use fixed replicas)
- **BUILD → DEPLOY → Verify RUNNING status**

### Phase 2: Add Parameterization (ONLY when user explicitly requests)

Add parameters ONE AT A TIME:
1. Add single API parameter to root service with `parameterDependencyMap`
2. Redefine the parameter on the child service (key + name + description + type — all required)
3. Replace hardcoded value with `$var.paramName` in child service
4. **RE-BUILD → RE-DEPLOY → Validate**
5. Repeat for each additional parameter only if user requests

### Phase 3: Add Advanced Features (ONLY when user explicitly requests)

- Add autoscaling (remove any `replicaCountAPIParam` first — they cannot coexist)
- Add custom replica count parameters
- Add storage parameterization
- Add load balancers if not already present
- Add integrations (observability, metering)
- Add action hooks
- **RE-BUILD → RE-DEPLOY → Validate**

## Image Registry Authentication

### Testing Image Accessibility

For each custom image (non-public images like postgres, nginx, redis are always public), test whether it is publicly accessible before assuming it needs credentials:

```bash
# Create temporary Docker config to test without local credentials
TEMP_DOCKER_CONFIG=$(mktemp -d)
DOCKER_CONFIG=$TEMP_DOCKER_CONFIG docker pull <image>:<tag> 2>&1
rm -rf $TEMP_DOCKER_CONFIG
```

- If pull succeeds: Image is public — no auth needed
- If pull fails with "unauthorized" or "denied": Image is private — configure auth below

### Credential Prompts by Registry Type

**Docker Hub (`docker.io`)**:
- Ask: "What is your Docker Hub username?"
- Ask: "Please create a Docker Hub Personal Access Token (PAT) at https://hub.docker.com/settings/security with read permissions. What should I name the secret?" (suggest: `DOCKERHUB_PASSWORD`)

**GitHub Container Registry (`ghcr.io`)**:
- Ask: "What is your GitHub username or organization?"
- Ask: "Please create a GitHub PAT at https://github.com/settings/tokens with `read:packages` scope. What should I name the username and token secrets?" (suggest: `GITHUB_USERNAME`, `GITHUB_TOKEN`)

**AWS ECR / GCP Artifact Registry / Azure ACR / Custom registry**:
- Ask: "What is the username for this registry?"
- Ask: "What should I name the password secret?" (suggest: `REGISTRY_PASSWORD`)

### Secret Creation Walkthrough (Omnistrate Console)

Guide the customer to create secrets before building:

```
1. Log into Omnistrate console: https://omnistrate.cloud
2. Navigate to: Services → [Your Service] → Environments → Dev → Secrets
3. Click "Add Secret"
4. Name: DOCKERHUB_PASSWORD (use the exact name agreed above)
5. Value: [Paste the PAT / token]
6. Click Save
7. Repeat steps 2–6 for the Prod environment (same secret name, same value)
```

Wait for confirmation that secrets have been created before building.

### `x-omnistrate-image-registry-attributes` Block

Search docs first: `mcp__ctl__docs_compose_spec_search query="x-omnistrate-image-registry-attributes"`

Add at the **top level** of the compose file (same level as `version:` and `services:`):

```yaml
version: '3.8'

x-omnistrate-image-registry-attributes:
  docker.io:          # Include ONLY if using private docker.io images
    auth:
      username: mycompany                       # Hardcoded OR {{ $secret.NAME }}
      password: {{ $secret.DOCKERHUB_PASSWORD }}
  ghcr.io:            # Include ONLY if using private ghcr.io images
    auth:
      username: {{ $secret.GITHUB_USERNAME }}
      password: {{ $secret.GITHUB_TOKEN }}
  registry.company.com:  # Include ONLY if using a custom private registry
    auth:
      username: registryuser
      password: {{ $secret.PRIVATE_REGISTRY_PASSWORD }}

services: [...]
```

**Rules**:
- Include ONLY registries that have private images — do not add unused entries
- Registry hostname must match the image URL prefix (e.g., `docker.io` for `mycompany/api:tag`)
- Username may be hardcoded; password/token MUST use `{{ $secret.NAME }}` syntax

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

**Note**: Use the simple `options` array (shown above). `labeledOptions` may not work in all contexts — prefer `options` for reliability.

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
    snapshotBeforeDeletion: true  # Optional: take final snapshot before deletion
```

**Backup Configuration Properties**:
- `backupRetentionInDays` (required) - Number of days to retain backups
- `backupPeriodInHours` (required) - Period in hours between automatic backups
- `snapshotBeforeDeletion` (optional) - Controls whether a final manual snapshot is automatically created before resource deletion. Defaults to `false` if not specified.

**Final Snapshot Behavior**:
When `snapshotBeforeDeletion: true`:
- A final manual snapshot is automatically created before instance deletion
- The snapshot persists even after the instance is deleted
- Can be used to restore the instance later or preserve data
- Can be overridden during deletion with `skipFinalSnapshot: true` flag

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

**Conflict rule**: `replicaCountAPIParam` and `autoscaling` cannot be used together on the same service — they are mutually exclusive. Remove `replicaCountAPIParam` from `x-omnistrate-compute` before adding autoscaling.

```yaml
# ❌ Wrong — causes build error
x-omnistrate-compute:
  replicaCountAPIParam: replicas
x-omnistrate-capabilities:
  autoscaling:
    minReplicas: 2
    maxReplicas: 10

# ✅ Correct — autoscaling only (no replicaCountAPIParam)
x-omnistrate-compute:
  instanceTypes:
    - cloudProvider: aws
      name: t3.xlarge
x-omnistrate-capabilities:
  autoscaling:
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
