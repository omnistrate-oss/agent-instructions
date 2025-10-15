# Omnistrate Service Onboarding Guide

This guide provides step-by-step instructions for transforming a Docker Compose file into an Omnistrate-enabled service definition using MCP tools.

## Prerequisites

Before starting, ensure you have:
1. **Original Docker Compose file** (v3.9+) ready
2. **Cloud accounts** connected to Omnistrate (check with `mcp__ctl__account_list`)
3. **Omnistrate CLI access** through MCP tools
4. Understanding of your service architecture and dependencies

## Critical Rules

1. **Never modify original files** - Create new `-omnistrate.yaml` file
2. **Search documentation first** - Use `mcp__ctl__docs_compose_spec_search` for every extension tag
3. **Use real cloud accounts** - Never use placeholder values
4. **Test incrementally** - Build and test after each major change
5. **Follow the order** - Complete phases sequentially
6. **No hallucinations** - Only use documented features and verified syntax
7. **When uncertain, skip** - If you lack confidence in a transformation, skip it and note what was skipped

## Step-by-Step Transformation Process

### Phase 1: Preparation and Discovery

#### Step 1.1: Analyze Source Compose File
```bash
# Read and understand the original compose file
Read the docker-compose.yaml file
```

**Actions:**
- Identify all services and their roles
- Map service dependencies (depends_on)
- Note environment variables that need parameterization
- Identify which service should be customer-facing (root)
- List volumes that need persistent storage

**Questions to answer:**
- Is this a single service or multi-service application?
- Which service is the primary entry point for customers?
- What configuration should customers be able to customize?
- Are there any stateful services requiring backups?

**Important: Confidence-based approach**
- Only transform elements you fully understand
- If unsure about a specific configuration, skip it and document why
- Do not guess at extension syntax - always search docs first
- It's better to have a working basic spec than a broken complex one

#### Step 1.2: Check Documentation for Extensions and System Parameters
```bash
# Search for compose spec extensions
mcp__ctl__docs_compose_spec_search query="x-omnistrate-service-plan"
mcp__ctl__docs_compose_spec_search query="x-omnistrate-api-params"
mcp__ctl__docs_compose_spec_search query="x-omnistrate-compute"

# Get system parameters schema (CRITICAL for $sys.* variables)
mcp__ctl__docs_system_parameters
```

**Always search docs for:**
- Service plan configuration
- API parameters
- Compute configuration
- Storage configuration
- Capabilities (backup, multi-zone, etc.)
- System parameters (for environment variable interpolation)
- Any other extension you plan to use

**Critical: Verification before use**
- If search returns no results, DO NOT use that extension
- If documentation is unclear, ask for clarification rather than guessing
- If you find conflicting information, note it and skip that feature
- Use `json_schema_only=true` flag to get schema validation for extensions
- **ALWAYS verify system parameter paths** using `mcp__ctl__docs_system_parameters` before using `$sys.*` variables

#### Step 1.3: Retrieve Cloud Accounts
```bash
# List available cloud accounts
mcp__ctl__account_list

# Get details for specific account
mcp__ctl__account_describe account-name="<account-name>"
```

**Select accounts:**
- Choose one cloud provider account (AWS, GCP, or Azure)
- If BYOC: You need customer's cloud account
- If Hosted: Use your service provider account
- Note down: Account ID, Bootstrap Role ARN (AWS) or Project ID (GCP)

**If no accounts:** Direct user to https://omnistrate.cloud/cloud-accounts and stop.

### Phase 2: Create Omnistrate Compose Spec

#### Step 2.1: Copy Original File
```bash
# Create new file (never modify original)
cp docker-compose.yaml docker-compose-omnistrate.yaml
```

#### Step 2.2: Add Service Plan Configuration

**At the top of the file, add:**
```yaml
version: "3.9"

x-omnistrate-service-plan:
  name: "<descriptive-plan-name>"
  tenancyType: "OMNISTRATE_DEDICATED_TENANCY"
  deployment:
    hostedDeployment:  # or byoaDeployment for BYOC
      # For AWS:
      AwsAccountId: "<from account describe>"
      AwsBootstrapRoleAccountArn: "<from account describe>"
      # For GCP:
      GcpProjectId: "<from account describe>"
      GcpProjectNumber: "<from account describe>"
      GcpServiceAccountEmail: "<from account describe>"
      # For Azure:
      AzureSubscriptionId: "<from account describe>"
      AzureTenantId: "<from account describe>"
```

**Important:**
- Use real values from Step 1.3 (account describe)
- For BYOC: Change `hostedDeployment` to `byoaDeployment`
- Only include cloud providers you'll deploy to
- Search docs if you need different tenancy types

#### Step 2.3: Determine Service Architecture

**Decision: Single Service vs. Multi-Service Application**

**Single Service Application:**
- Compose file has exactly ONE service
- That service becomes the root (customer-facing)
- Set `x-omnistrate-mode-internal: false` on the service
- Define API parameters directly on that service
- No need for synthetic root service

**Multi-Service Application:**
- Compose file has 2+ services (database, API, cache, worker, etc.)
- Need to create a synthetic root service
- All original services become internal children
- Root service orchestrates dependencies and parameters

**Decision Criteria:**
```
Count services in original compose file:
  If count == 1: Single service pattern
  If count >= 2: Multi-service pattern (create root)
```

**Example Analysis:**
```yaml
# Original compose - is this single or multi-service?
services:
  database:      # Service 1
    image: vendor/database:latest
  cache:  # Service 2
    image: vendor/cache:latest

# Count = 2, therefore: MULTI-SERVICE → Create root service
```

#### Step 2.3a: Add Root Service (Multi-Service Apps Only)

**Create synthetic root service:**

```yaml
services:
  <app-name>:  # Choose descriptive non-conflicting name
    image: omnistrate/noop
    x-omnistrate-mode-internal: false  # Root service = false
    depends_on:
      - <service-1>
      - <service-2>
      # List ALL original services here
    x-omnistrate-api-params:
      # Define ALL customer-facing parameters here
      # These flow to child services via parameterDependencyMap
```

**Naming the root service:**
- Choose name reflecting overall application (e.g., "my-application" or "platform-name")
- Must NOT conflict with existing service names
- Should be customer-friendly (shown in portal)

**Rules:**
- Root service uses `omnistrate/noop` image (does not run a container)
- Root service has `x-omnistrate-mode-internal: false`
- Root service depends on ALL other services
- Root service defines ALL customer-facing API parameters
- Root service should have backup configuration (if stateful)
- Root service does NOT define compute/storage (noop doesn't need resources)

#### Step 2.4: Mark Child Services as Internal

**For each service that was in the original compose:**

```yaml
  <original-service-name>:
    x-omnistrate-mode-internal: true  # Mark as internal
    image: <original-image>
    # ... rest of original configuration
```

**Rules:**
- All non-root services must have `x-omnistrate-mode-internal: true`
- Keep original service names
- Keep original images and ports

#### Step 2.5: Define API Parameters

**Search docs first:**
```bash
mcp__ctl__docs_compose_spec_search query="x-omnistrate-api-params"
```

**On root service, add API parameters:**
```yaml
x-omnistrate-api-params:
  - key: <paramName>
    description: "<User-friendly description>"
    name: "<Display Name>"
    type: String  # or Float64, Boolean, Password
    modifiable: true  # Can customer change after creation?
    required: true
    defaultValue: "<default-value>"
    export: true  # Show in customer portal?
    parameterDependencyMap:
      <child-service-name>: <paramName>  # Flow to child
```

**What to parameterize:**
- Instance types
- Number of replicas
- Storage sizes
- Application-specific config (database names, cache sizes, etc.)
- Passwords and secrets

**Parameter types:**
- `String` - Text values, instance types, names
- `Float64` - Numbers, replica counts, sizes
- `Boolean` - Enable/disable features
- `Password` - Sensitive values (export: false)

**Parameter flow patterns:**

**Pattern 1: Simple flow (root → child)**
```yaml
# Root service
services:
  app:
    x-omnistrate-api-params:
      - key: cacheSize
        type: Float64
        defaultValue: "100"
        parameterDependencyMap:
          redis: cacheSize  # Flow to redis service

# Child service (receives parameter)
  redis:
    x-omnistrate-mode-internal: true
    environment:
      - MAX_MEMORY=$var.cacheSize  # Use parameter
```

**Pattern 2: Dual definition (parameter on both root and child)**

**When to use:** Parameter affects child service's **infrastructure configuration** (compute, storage, replicas)

```yaml
# Root service
services:
  app:
    x-omnistrate-api-params:
      - key: instanceType
        type: String
        defaultValue: "e2-standard-4"
        parameterDependencyMap:
          backend: instanceType  # Flow to child

# Child service (MUST redefine for compute/storage use)
  backend:
    x-omnistrate-mode-internal: true
    x-omnistrate-api-params:
      - key: instanceType  # Redefine for infrastructure use
        type: String
    x-omnistrate-compute:
      instanceTypes:
        - cloudProvider: gcp
          apiParam: instanceType  # Uses parameter for compute
```

**Why dual definition is required:**

Omnistrate evaluates infrastructure configuration (compute, storage) at the service level. For a parameter to be used in `x-omnistrate-compute` or `x-omnistrate-storage`, it MUST be defined directly on that service.

**Decision tree for dual definition:**
```
Will parameter be used in x-omnistrate-compute or x-omnistrate-storage?
  YES → Dual definition required (define on both root and child)
  NO → Simple flow sufficient (define only on root)

Examples:
- instanceType (affects compute) → Dual definition ✅
- numReplicas (affects compute) → Dual definition ✅
- storageSize (affects storage) → Dual definition ✅
- databasePassword (used in environment) → Simple flow ✅
- cacheSize (used in environment) → Simple flow ✅
```

**Pattern 3: Chained flow (root → child1 → child2)**
```yaml
# Root service
services:
  app:
    x-omnistrate-api-params:
      - key: clusterName
        type: String
        defaultValue: "primary"
        parameterDependencyMap:
          database: clusterName
          cache: clusterName  # Flow to multiple children

# Child services receive same parameter
  database:
    environment:
      - CLUSTER_NAME=$var.clusterName
  cache:
    environment:
      - CLUSTER_NAME=$var.clusterName
```

**Pattern 4: Parameter with options (dropdown in portal)**
```yaml
x-omnistrate-api-params:
  - key: persistenceMode
    type: String
    defaultValue: "low"
    options:
      - "low"
      - "medium"
      - "high"
    description: "RDB persistence configuration level"
```

**Pattern 5: Parameter with bounds (validation)**
```yaml
x-omnistrate-api-params:
  - key: maxQueuedQueries
    type: Float64
    defaultValue: "50"
    min: 1
    max: 1000
    description: "Maximum number of queries in queue"
```

**Note:** Use `min` and `max` (NOT `minValue`/`maxValue`) for parameter bounds.

**Common mistakes:**
- ❌ Using `$var.X` without defining parameter
- ❌ Defining parameter only on child (must be on root)
- ❌ Wrong parameter name in `parameterDependencyMap`
- ❌ Mixing up `key` (internal name) and `name` (display name)

**Rules:**
1. ALL customer-facing parameters defined on root service
2. Use `parameterDependencyMap` to flow to children
3. Children CAN redefine parameter for visibility (dual definition)
4. Every `$var.X` in environment MUST have matching parameter
5. Use `options` for dropdowns, `minValue`/`maxValue` for ranges

#### Step 2.6: Transform Environment Variables

**Search for variable interpolation syntax:**
```bash
mcp__ctl__docs_compose_spec_search query="environment variables"
```

**Replace hardcoded values with parameter references:**

Original:
```yaml
environment:
  - DATABASE_URL=postgresql://user:pass@db:5432/app
  - CACHE_SIZE=100
```

Transformed:
```yaml
services:
  backend:
    depends_on:
      - database  # Required for cross-service reference
    environment:
      - DATABASE_URL="{{ $var.protocol }}://{{ $var.dbUser }}:{{ $var.dbPassword }}@{{ $database.sys.network.externalEndpoint }}:5432/{{ $var.dbName }}"
      - CACHE_SIZE="${var.cacheSize}"
      - NODE_HOST="${sys.network.node.externalEndpoint}"
```

**Variable types:**

**1. API Parameters: `$var.<paramName>`**
- Customer-defined values
- Must have corresponding `x-omnistrate-api-params` definition
- Examples: `$var.dbPassword`, `$var.cacheSize`, `$var.masterName`

**2. System Variables: `$sys.*`**

**CRITICAL: String Concatenation with System Parameters**

When you need to concatenate system parameters with other strings (like ports or paths), you MUST use the `{{ }}` syntax:

```yaml
environment:
  # ✅ CORRECT - Using {{ }} for concatenation
  - FRONTEND_URL="{{ $sys.network.node.externalEndpoint }}:8080"
  - API_URL="{{ $sys.network.node.externalEndpoint }}/api"
  - ELASTICSEARCH_URL="{{ $sys.network.node.externalEndpoint }}:9200"
  
  # ❌ INCORRECT - Will fail validation
  - FRONTEND_URL=$sys.network.node.externalEndpoint:8080
  - API_URL=$sys.network.node.externalEndpoint/api
```

**Rules for concatenation:**
- Use `{{ $sys.* }}` when concatenating with ports, paths, or any other text
- Use `$sys.*` (without brackets) only when using the value alone

**Examples:**

```yaml
environment:
  # System parameter alone (no concatenation)
  - MY_HOST=$sys.network.node.externalEndpoint
  
  # System parameter with port concatenation
  - MY_URL="{{ $sys.network.node.externalEndpoint }}:3000"
  
  # System parameter with path concatenation
  - WEBHOOK_URL="{{ $sys.network.node.externalEndpoint }}/webhooks"
  
  # Multiple system parameters in one string
  - CONNECTION="{{ $sys.deployment.cloudProvider }}-{{ $sys.deploymentCell.region }}"
  
  # Mixing API params and system params
  - FULL_URL="{{ $sys.network.node.externalEndpoint }}:{{ $var.port }}"
```

**CRITICAL: Always look up system parameters dynamically**

System parameters evolve and should NOT be hardcoded. Always use the tool to get current schema:

```bash
# Get the complete JSON schema for system parameters
mcp__ctl__docs_system_parameters
```

**How to use system parameters:**

1. **Identify what you need** (e.g., network endpoint, cloud provider, instance type)
2. **Look up the schema** using `mcp__ctl__docs_system_parameters`
3. **Navigate the JSON schema** to find the exact path for your parameter
4. **Verify the path exists** in the current schema version
5. **Use the verified path** in your environment variables

**Example workflow:**

```bash
# Step 1: Get the schema
mcp__ctl__docs_system_parameters

# Step 2: Examine the JSON structure to find what you need
# Look for network parameters, compute parameters, deployment info, etc.

# Step 3: Use the EXACT path you found in the schema
# Example format (paths will vary based on actual schema):
environment:
  - MY_VARIABLE="${sys.<category>.<subcategory>.<field>}"
```

**Important notes:**
- Parameter paths change over time - always verify against current schema
- Do not assume a parameter exists - check the schema first
- If a parameter you need doesn't exist in schema, document it as a gap

**3. Cross-Service References: `$<service-name>.sys.*`**

**Reference other service's network info:**
```yaml
# In cache service, reference database service
environment:
  - DATABASE_HOST="${database.sys.network.externalClusterEndpoint}"
  - DATABASE_PORT="5432"
```

**Critical requirement: `depends_on` relationship**

A service can ONLY reference another service's system variables if it declares a `depends_on` relationship:

```yaml
services:
  cache:
    depends_on:
      - database  # REQUIRED for cross-service reference
    environment:
      - DATABASE_HOST="${database.sys.network.externalClusterEndpoint}"
```

**Syntax:**
- Format: `"${<service-name>.sys.<variable-path>}"`
- Service name must match exactly
- Referencing service MUST have `depends_on` relationship to referenced service

**Complete example:**
```yaml
services:
  backend:
    depends_on:
      - redis
      - postgres  # REQUIRED for cross-service references below
    environment:
      # API parameter
      - DB_PASSWORD="${var.dbPassword}"

      # Current service network
      - SELF_IP="${sys.network.node.externalEndpoint}"

      # Cross-service reference (requires depends_on)
      - REDIS_HOST="${redis.sys.network.externalClusterEndpoint}"
      - POSTGRES_HOST="${postgres.sys.network.node.externalEndpoint}"

      # Deployment metadata (verified from system-parameters schema)
      - DEPLOYMENT_REGION="${sys.deploymentCell.region}"
      - CLOUD_PROVIDER="${sys.deployment.cloudProvider}"
      - INSTANCE_ID="${sys.id}"

      # Compute metadata
      - CPU_CORES="${sys.compute.node.cores}"
      - MEMORY_BYTES="${sys.compute.node.memory}"
```

**Validation reminder:**
Before using any `$sys.*` variable, verify it exists in the schema:
```bash
mcp__ctl__docs_system_parameters
# Check the JSON schema to confirm the exact path
```

**Template string interpolation for complex strings:**

The `{{ }}` syntax is used for string concatenation and complex string building:

```yaml
environment:
  # Simple concatenation - system parameter with port
  - API_ENDPOINT="{{ $sys.network.node.externalEndpoint }}:8000"
  
  # Simple concatenation - system parameter with path
  - WEBHOOK_URL="{{ $sys.network.node.externalEndpoint }}/webhooks"
  
  # Complex connection string with multiple variable types
  - DATABASE_URL="{{ $var.protocol }}://{{ $var.dbUser }}:{{ $var.dbPassword }}@{{ $postgres.sys.network.externalEndpoint }}:{{ $var.dbPort }}/{{ $var.dbName }}"
  
  # Multiple system parameters
  - DEPLOYMENT_INFO="{{ $sys.deployment.cloudProvider }}-{{ $sys.deploymentCell.region }}"
```

**Key differences:**

```yaml
# Without concatenation (value used alone)
- MY_HOST=$sys.network.node.externalEndpoint
- MY_USER=$var.username

# With concatenation (value combined with other text)
- MY_URL="{{ $sys.network.node.externalEndpoint }}:3000"
- MY_CONNECTION="{{ $var.username }}@{{ $sys.network.node.externalEndpoint }}"
```

**Common patterns:**

**Pattern 1: Database connection strings**
```yaml
services:
  backend:
    depends_on:
      - postgres
    environment:
      - DATABASE_URL="{{ $var.protocol }}://{{ $var.dbUser }}:{{ $var.dbPassword }}@{{ $postgres.sys.network.externalEndpoint }}:5432/{{ $var.dbName }}"
```

**Pattern 2: Service endpoints with ports**
```yaml
services:
  frontend:
    environment:
      - FRONTEND_URL="{{ $sys.network.node.externalEndpoint }}:8080"
      - API_URL="{{ $sys.network.node.externalEndpoint }}:8000"
      - METRICS_URL="{{ $sys.network.node.externalEndpoint }}:9090/metrics"
```

**Pattern 3: Service discovery**
```yaml
services:
  backend:
    depends_on:
      - cache
    environment:
      - CACHE_URL="{{ $cache.sys.network.externalClusterEndpoint }}:6379"
      - CACHE_HOST=$cache.sys.network.externalClusterEndpoint
      - CACHE_PASSWORD=$var.cachePassword
```

**Pattern 3: Dynamic configuration**
```yaml
environment:
  - CONFIG_FILE="/config/${sys.deployment.cloudProvider}-${sys.deploymentCell.region}.json"
  - LOG_LEVEL="${var.logLevel}"
```

**Rules:**
- Every `$var.X` must have corresponding API parameter
- System variables are automatically available BUT must be validated
- **CRITICAL**: Verify system variable paths using `mcp__ctl__docs_system_parameters` before use
- Cross-service references REQUIRE `depends_on` relationship
- Use `{{ }}` syntax for complex interpolations with multiple variables
- Use exact service names (case-sensitive)
- If a system variable doesn't exist in the schema, DO NOT use it

#### Step 2.7: Configure Compute Resources

**Search docs:**
```bash
mcp__ctl__docs_compose_spec_search query="x-omnistrate-compute"
```

**Add compute configuration to each service:**

```yaml
  <service-name>:
    x-omnistrate-compute:
      # If customer chooses instance type:
      instanceTypes:
        - cloudProvider: gcp
          apiParam: nodeInstanceType  # References API parameter
        - cloudProvider: aws
          apiParam: nodeInstanceType
      # If fixed instance type:
      instanceTypes:
        - cloudProvider: gcp
          name: e2-standard-4
        - cloudProvider: aws
          name: t3.xlarge
      # If customer chooses replica count:
      replicaCountAPIParam: numReplicas
      # If fixed replica count:
      replicaCount: 3
```

**Instance type selection:**
- Option 1: Let customer choose (use `apiParam`)
- Option 2: Fixed per cloud (use `name`)
- Never mix `apiParam` and `name` for same cloud

**For GPU workloads:**
```bash
# Search for GPU-enabled instance types
mcp__ctl__docs_compose_spec_search query="gpu instance types"
```

#### Step 2.8: Configure Storage Volumes

**Search docs:**
```bash
mcp__ctl__docs_compose_spec_search query="x-omnistrate-storage"
```

**Transform volume definitions:**

Original:
```yaml
volumes:
  - ./data:/data
```

Transformed:
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
```

**Storage types by cloud:**
- GCP: `GCP::PD_BALANCED`, `GCP::PD_SSD`, `GCP::PD_STANDARD`
- AWS: `AWS::EBS_GP3`, `AWS::EBS_GP2`, `AWS::EBS_IO1`
- Azure: `Azure::STANDARD_LRS`, `Azure::PREMIUM_LRS`

**Rules:**
- Define storage for all clouds you support
- Use appropriate sizes (Gi = gibibytes)
- Consider making size an API parameter for flexibility

#### Step 2.9: Add Capabilities

**Search docs:**
```bash
mcp__ctl__docs_compose_spec_search query="x-omnistrate-capabilities"
```

**Common capabilities:**

```yaml
x-omnistrate-capabilities:
  # Backup configuration (only on root or stateful services)
  backupConfiguration:
    backupRetentionInDays: 7
    backupPeriodInHours: 24
  # Multi-zone deployment
  enableMultiZone: true
  # Endpoint per replica
  enableEndpointPerReplica: true
  # Autoscaling
  autoscalingConfig:
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilization: 80
```

**When to use:**
- `backupConfiguration` - Stateful services (databases, storage)
- `enableMultiZone` - High availability requirements
- `enableEndpointPerReplica` - Load balancing across replicas
- `autoscalingConfig` - Variable load patterns

**Backup Configuration Placement:**

**Rule: Backups ONLY on services with `x-omnistrate-mode-internal: false`**

**Multi-service application (with root service):**
```yaml
services:
  app:  # Root service
    image: omnistrate/noop
    x-omnistrate-mode-internal: false  # Can have backups
    x-omnistrate-capabilities:
      backupConfiguration:
        backupRetentionInDays: 7
        backupPeriodInHours: 24

  database:  # Child service
    x-omnistrate-mode-internal: true  # NO backups allowed
    # Do NOT add backupConfiguration here

  cache:  # Child service
    x-omnistrate-mode-internal: true  # NO backups allowed
```

**Single-service application:**
```yaml
services:
  database:  # Only service = root
    x-omnistrate-mode-internal: false  # Can have backups
    x-omnistrate-capabilities:
      backupConfiguration:
        backupRetentionInDays: 7
```

**Decision tree for backups:**
```
Is this a multi-service application?
  YES → Add backups to root service (omnistrate/noop) ONLY
  NO → Add backups to the single service (if stateful)

Is any service stateful (database, volumes)?
  YES → Add backupConfiguration
  NO → Skip backups
```

**Rules:**
- ❌ Never add backups to services with `x-omnistrate-mode-internal: true`
- ✅ Backups on root service (multi-service) or single service only
- ✅ Only enable backups if service is stateful (has volumes, databases)
- ❌ Don't enable autoscaling with fixed `replicaCount`
- Search docs for specific capability schemas

#### Step 2.10: Add Load Balancers (If Needed)

**Search docs:**
```bash
mcp__ctl__docs_compose_spec_search query="x-omnistrate-load-balancer"
```

**Decision: Do I need a load balancer?**

**Load balancer required when:**
1. ✅ Service has multiple replicas (replicaCount > 1 or autoscaling)
2. ✅ External clients need single endpoint for replicas
3. ✅ Non-HTTP services (databases, caches) need TCP load balancing
4. ✅ Custom port mapping between ingress and backend

**Load balancer NOT needed when:**
1. ❌ Single replica service (replicaCount = 1)
2. ❌ Service only accessed internally by other services
3. ❌ Root service using omnistrate/noop (no actual container)

**Decision tree:**
```
Does service have replicas > 1?
  NO → Skip load balancer
  YES → Continue

Is service accessed externally?
  NO → Skip load balancer (internal only)
  YES → Continue

Is service HTTP/HTTPS?
  YES → Use http load balancer
  NO → Use tcp load balancer
```

**Add at top level (not under services):**

**TCP Load Balancer (for databases, caches, non-HTTP services):**
```yaml
x-omnistrate-load-balancer:
  tcp:
    - name: "<LB Name>"
      description: "<LB Description>"
      ports:
        - associatedResourceKeys:
            - <service-1>  # Service name from compose
            - <service-2>  # Multiple services can share LB
          ingressPort: 6379  # External port clients connect to
          backendPort: 6379  # Container port service listens on
```

**HTTP Load Balancer (for web services, APIs):**
```yaml
x-omnistrate-load-balancer:
  http:
    - name: "<HTTP LB Name>"
      description: "<HTTP LB Description>"
      ports:
        - associatedResourceKeys:
            - <service-1>
          ingressPort: 80  # External port (80 or 443)
          backendPort: 8080  # Container port
      healthCheck:
        path: /health  # Health check endpoint
        port: 8080
        intervalSeconds: 30
        timeoutSeconds: 5
```

**Both TCP and HTTP (multiple load balancers):**
```yaml
x-omnistrate-load-balancer:
  tcp:
    - name: "Redis LB"
      ports:
        - associatedResourceKeys: [redis]
          ingressPort: 6379
          backendPort: 6379
  http:
    - name: "API LB"
      ports:
        - associatedResourceKeys: [api]
          ingressPort: 80
          backendPort: 8080
      healthCheck:
        path: /health
        port: 8080
```

**Common patterns:**

**Pattern 1: Database cluster (TCP)**
```yaml
x-omnistrate-load-balancer:
  tcp:
    - name: "PostgreSQL Cluster LB"
      description: "Load balancer for PostgreSQL replicas"
      ports:
        - associatedResourceKeys:
            - postgres-primary
            - postgres-replica
          ingressPort: 5432
          backendPort: 5432
```

**Pattern 2: API with health check (HTTP)**
```yaml
x-omnistrate-load-balancer:
  http:
    - name: "API Gateway LB"
      description: "Load balancer for API service"
      ports:
        - associatedResourceKeys:
            - api
          ingressPort: 443
          backendPort: 8080
      healthCheck:
        path: /api/health
        port: 8080
        intervalSeconds: 10
        timeoutSeconds: 3
```

**Pattern 3: Multi-port service (database + cache)**
```yaml
x-omnistrate-load-balancer:
  tcp:
    - name: "Database LB"
      ports:
        - associatedResourceKeys: [database, cache]
          ingressPort: 5432
          backendPort: 5432
    - name: "Cache LB"
      ports:
        - associatedResourceKeys: [database, cache]
          ingressPort: 6379
          backendPort: 6379
```

**Rules:**
- Load balancer is top-level (not under services)
- `associatedResourceKeys` must match service names exactly
- `ingressPort` = what clients connect to
- `backendPort` = what container listens on
- Only add if service has replicas > 1
- HTTP LB should have health checks

#### Step 2.11: Add ActionHooks (Lifecycle Management)

**Search docs:**
```bash
mcp__ctl__docs_compose_spec_search query="x-omnistrate-actionhooks"
```

**ActionHooks allow custom scripts at lifecycle events:**

**Add to services needing health checks or lifecycle actions:**
```yaml
services:
  <service-name>:
    x-omnistrate-actionhooks:
      - scope: NODE
        type: HEALTH_CHECK
        command: |
          #!/bin/bash
          # Health check script
          # Exit 0 = healthy, non-zero = unhealthy

          # Example: Check if service is responding
          curl -f http://localhost:8080/health || exit 1

          # Example: Check specific port
          nc -z localhost 6379 || exit 1

          exit 0
        timeout: 30  # Seconds
        retries: 3
```

**Common ActionHook types:**

**1. Health Check (most common)**
```yaml
x-omnistrate-actionhooks:
  - scope: NODE
    type: HEALTH_CHECK
    command: |
      #!/bin/bash
      # Verify service is ready
      curl -f http://localhost:8080/health || exit 1
      exit 0
    timeout: 30
    retries: 3
```

**2. Post-Start Hook**
```yaml
x-omnistrate-actionhooks:
  - scope: NODE
    type: POST_START
    command: |
      #!/bin/bash
      # Run after container starts
      # Initialize database, load data, etc.
      /app/init-db.sh
      exit 0
    timeout: 300
```

**3. Pre-Stop Hook**
```yaml
x-omnistrate-actionhooks:
  - scope: NODE
    type: PRE_STOP
    command: |
      #!/bin/bash
      # Run before container stops
      # Graceful shutdown, drain connections
      /app/graceful-shutdown.sh
      exit 0
    timeout: 120
```

**4. REMOVE Hook (for graceful failover in clustered services)**
```yaml
x-omnistrate-actionhooks:
  - scope: NODE
    type: REMOVE
    commandTemplate: |
      #!/bin/bash
      # Executed when node is being removed from cluster
      # Use for graceful failover before removal

      # Example: Check if this is the primary node
      role=$(curl -s http://localhost:8080/role)
      if [ "$role" == "primary" ]; then
          # Trigger failover to standby before removing primary
          curl -X POST http://$COORDINATOR_HOST/failover -d "node=$HOSTNAME"
          # Wait for failover to complete
          sleep 10
      fi
      exit 0
    timeout: 120
```

**Key difference: `command` vs `commandTemplate`**

- **`command`**: Static script, same for all nodes
  - Use for simple checks, standard initialization
  - Example: Health checks, basic startup scripts

- **`commandTemplate`**: Dynamic script with environment variable substitution
  - Use when script needs node-specific information
  - Environment variables like `$NODE_PORT`, `$SENTINEL_HOST` are interpolated at runtime
  - Example: REMOVE hooks that check node role before action

**REMOVE Hook Use Cases:**
- ✅ Clustered databases needing failover (primary/replica setups)
- ✅ Services with leader election
- ✅ Stateful services requiring state transfer
- ✅ Services with external dependency cleanup
- ❌ Stateless services (no special removal needed)

**When to use ActionHooks:**
- ✅ Custom health check logic beyond port checks
- ✅ Complex initialization requiring external commands
- ✅ Graceful shutdown procedures
- ✅ Service-specific readiness validation
- ❌ Simple HTTP endpoints (use native health checks instead)
- ❌ Long-running background tasks (use separate service)

**Health Check Script Best Practices:**
```bash
#!/bin/bash
# Multiple checks with proper error handling

# Check 1: Port is listening
nc -z localhost 8080 || {
  echo "Port 8080 not listening"
  exit 1
}

# Check 2: Service responds correctly
response=$(curl -s http://localhost:8080/health)
if [ "$response" != "OK" ]; then
  echo "Service not responding correctly"
  exit 1
fi

# Check 3: Service is not in error state
error_count=$(curl -s http://localhost:8080/metrics | grep -c "errors")
if [ "$error_count" -gt 0 ]; then
  echo "Service has errors"
  exit 1
fi

echo "Health check passed"
exit 0
```

**Environment variables available in ActionHooks:**
- `$sys.*` variables from Omnistrate
- `$var.*` API parameters
- Standard container environment variables

#### Step 2.12: Add Integrations

**Search docs:**
```bash
mcp__ctl__docs_compose_spec_search query="x-omnistrate-integrations"
```

**Add at top level:**

```yaml
x-omnistrate-integrations:
  - omnistrateLogging:  # Native logging
  - omnistrateMetrics: {}  # Native metrics
```

**Optional advanced integrations:**
```yaml
x-internal-integrations:
  logs:
    provider: native
  metrics:
    provider: native
```

**Custom metrics (if needed):**
```yaml
x-omnistrate-integrations:
  - omnistrateMetrics:
      metrics:
        - metricName: "query_latency"
          metricType: "gauge"
          metricUnit: "milliseconds"
          metricPath: "/metrics"
          metricPort: 9090
        - metricName: "active_connections"
          metricType: "counter"
          metricPath: "/metrics"
          metricPort: 9090
```

#### Step 2.13: Add Custom Vendor Metrics (Advanced)

**For application-specific metrics beyond standard observability:**

**Search docs:**
```bash
mcp__ctl__docs_compose_spec_search query="custom metrics"
```

**Vendor-specific metrics extensions:**

Omnistrate supports custom metric definitions using vendor-specific extensions with the format `x-<vendorName>Metrics`.

**Pattern: Define reusable metrics with YAML anchors**
```yaml
# At top level, define metrics configuration
x-customMetrics: &metrics  # YAML anchor for reusability
  prometheusEndpoint: "http://localhost:9090/metrics"
  metrics:
    http_requests_duration_bucket:
      "Request Latency (μs) Bucket":
        aggregationFunction: sum
        description: "Latency distribution of HTTP requests"
    active_connections:
      "Active Connections":
        aggregationFunction: avg
        description: "Number of active connections"
    memory_used_bytes:
      "Memory Used (Bytes)":
        aggregationFunction: max
        description: "Total memory used by service"
```

**Use anchor in services:**
```yaml
services:
  backend:
    x-omnistrate-integrations:
      - x-customMetrics: *metrics  # Reference anchor
```

**Custom metrics structure:**
```yaml
x-<vendorName>Metrics:
  prometheusEndpoint: "<endpoint-url>"  # Where to scrape metrics
  metrics:
    <prometheus_metric_name>:  # Exact metric name from Prometheus
      "<Display Name>":  # Human-readable name for dashboards
        aggregationFunction: <sum|avg|max|min|count>
        description: "<metric description>"
        unit: "<unit>"  # Optional
```

**Common aggregation functions:**
- `sum` - Total across all nodes (throughput, total requests)
- `avg` - Average across nodes (latency, utilization)
- `max` - Maximum value (peak memory, max connections)
- `min` - Minimum value (rarely used)
- `count` - Count of occurrences

**Complete example:**
```yaml
x-customMetrics: &appMetrics
  prometheusEndpoint: "http://localhost:9090/metrics"
  metrics:
    # Throughput metric
    http_requests_total:
      "Total HTTP Requests":
        aggregationFunction: sum
        description: "Total number of HTTP requests handled"

    # Latency metric (percentile buckets)
    http_request_duration_seconds_bucket:
      "Request Duration (seconds) Bucket":
        aggregationFunction: sum
        description: "Distribution of request durations"

    # Resource metric
    process_resident_memory_bytes:
      "Process Memory (Bytes)":
        aggregationFunction: max
        description: "Memory used by the process"

    # Queue metric
    queue_depth:
      "Queue Depth":
        aggregationFunction: avg
        description: "Average number of items in queue"

services:
  api:
    x-omnistrate-integrations:
      - x-customMetrics: *appMetrics
```

**YAML Anchors for reusability:**

If multiple services expose the same metrics:
```yaml
# Define once with anchor
x-dbMetrics: &dbMetrics
  prometheusEndpoint: "http://localhost:9187/metrics"
  metrics:
    # ... metric definitions

services:
  database-primary:
    x-omnistrate-integrations:
      - x-dbMetrics: *dbMetrics  # Reference

  database-replica:
    x-omnistrate-integrations:
      - x-dbMetrics: *dbMetrics  # Reuse same config
```

**When to use custom metrics:**
- ✅ Application exposes Prometheus metrics
- ✅ Need visibility into app-specific operations (queries, transactions)
- ✅ Want to track business metrics (user activity, revenue)
- ✅ Monitoring performance bottlenecks specific to your service
- ❌ Standard infrastructure metrics (CPU, memory) - use native integration

**Rules:**
- Metric names must match Prometheus metric names exactly
- Use descriptive display names for dashboards
- Choose appropriate aggregation function for metric type
- Test metrics endpoint is accessible from containers
- Document metrics in your service README

### Phase 3: Build, Deploy, and Iterate

**IMPORTANT**: You are expected to fully onboard the transformed compose spec through Omnistrate and iterate until you have a running instance. This includes:
1. Building the service
2. Creating service plans
3. Deploying test instances
4. Debugging deployment failures
5. Fixing issues and redeploying
6. Iterating until instance is RUNNING and healthy

**For detailed debugging instructions, refer to**: `FDE-Debugging.md`

The debugging guide provides systematic approaches for:
- Analyzing failed deployments
- Workflow event analysis
- Pod-level debugging with kubectl
- Helm-specific debugging
- Common failure patterns and solutions

#### Step 3.1: Schema Validation

**For critical extensions, validate using schema:**
```bash
# Get JSON schema for extension
mcp__ctl__docs_compose_spec_search query="x-omnistrate-compute" json_schema_only=true

# Review schema to ensure your configuration is correct
```

#### Step 3.2: Build Service

**Attempt to build:**
```bash
mcp__ctl__build_compose file="docker-compose-omnistrate.yaml" service_name="<service-name>" description="<description>"
```

**Common build errors:**
- **Validation errors**: Missing required fields, wrong types
  - Fix: Check schema with `json_schema_only` flag
- **Cloud account errors**: Invalid account IDs
  - Fix: Re-run account describe and update values
- **Parameter errors**: Missing parameter definitions
  - Fix: Ensure all `$var.X` have corresponding API params

**If build succeeds:**
- Note the service ID returned
- Proceed to deployment testing

#### Step 3.3: Create Service Plan

**List service plans:**
```bash
mcp__ctl__service_plan_list service_name="<service-name>"
```

**Describe plan:**
```bash
mcp__ctl__service_plan_describe service_name="<service-name>" plan_name="<plan-name>"
```

#### Step 3.4: Deploy Test Instance

**Create instance:**
```bash
mcp__ctl__instance_create \
  service_name="<service-name>" \
  plan_name="<plan-name>" \
  environment="prod" \
  cloud_provider="gcp" \
  region="us-central1" \
  instance_name="test-instance"
```

**Monitor deployment:**
```bash
# Check deployment status
mcp__ctl__instance_describe \
  service_name="<service-name>" \
  instance_id="<instance-id>" \
  deployment_status=true

# If deployment fails, check workflows
mcp__ctl__workflow_list \
  service_name="<service-name>" \
  environment="prod" \
  instance_id="<instance-id>"

# Get workflow details
mcp__ctl__workflow_events \
  service_name="<service-name>" \
  environment="prod" \
  workflow_id="<workflow-id>"
```

#### Step 3.5: Debug and Iterate Until RUNNING

**You MUST iterate until instance is RUNNING and healthy. Do not stop at first failure.**

**Systematic debugging approach (detailed in FDE-Debugging.md):**

1. **Check deployment status**: `mcp__ctl__instance_describe --deployment-status`
2. **Analyze workflow events**: `mcp__ctl__workflow_list` and `mcp__ctl__workflow_events`
3. **Deep-dive failed resources**: Use targeted queries for specific resources
4. **Pod-level debugging**: Use `mcp__ctl__deployment_cell_update_kubeconfig` + kubectl if needed
5. **Helm debugging**: Check Helm release status for Helm-based resources

**Common issues and fixes:**

1. **Instance type unavailable in region**
   - Fix: Use different instance type or region
   - Search: `mcp__ctl__docs_compose_spec_search query="instance types"`

2. **Volume creation failed**
   - Fix: Check storage type compatibility with instance type
   - Fix: Reduce storage size if hitting quota limits

3. **Health check failures / Startup probe failures**
   - Fix: Check application logs with kubectl logs
   - Fix: Verify service dependencies are running
   - Fix: Check environment variable configuration
   - Fix: Look for application syntax or runtime errors

4. **Environment variable errors**
   - Fix: Ensure all `$var` references have parameters
   - Fix: Verify system variable paths with `mcp__ctl__docs_system_parameters`

5. **Service dependency timeout**
   - Fix: Verify depends_on chain
   - Fix: Check network connectivity between services
   - Fix: Ensure cross-service references use correct syntax

**Iteration loop:**
1. Deploy instance
2. Monitor deployment status
3. If FAILED or stuck in DEPLOYING:
   - Refer to FDE-Debugging.md for systematic analysis
   - Identify root cause from workflow events/pod logs
   - Fix the issue in compose spec or configuration
4. Build new service version
5. Delete failed instance (if needed)
6. Deploy again
7. **Repeat until instance is RUNNING and healthy**

**Do not give up after first failure. Most deployments require 2-3 iterations to succeed.**

### Phase 4: Production Readiness

#### Step 4.1: Validate Complete Configuration

**Checklist:**
- [ ] All services have appropriate compute resources
- [ ] All stateful services have backup configuration
- [ ] All customer-facing parameters are defined
- [ ] Environment variables use parameters (no hardcoded values)
- [ ] Storage volumes are appropriately sized
- [ ] Load balancers configured for multi-replica services
- [ ] Integrations enabled (logging, metrics)
- [ ] Health checks defined for critical services

#### Step 4.2: Test Multi-Instance Deployment

**Deploy multiple instances:**
```bash
# Deploy instance 1
mcp__ctl__instance_create service_name="<service>" instance_name="customer-1" ...

# Deploy instance 2
mcp__ctl__instance_create service_name="<service>" instance_name="customer-2" ...

# Verify isolation
mcp__ctl__instance_list service_name="<service>"
```

**Verify:**
- Each instance is isolated
- Instances don't interfere with each other
- Each has dedicated resources

#### Step 4.3: Document Final Configuration

**Create README.md documenting:**
- API parameters and their purposes
- Recommended instance types per cloud
- Backup and restore procedures
- Scaling considerations
- Monitoring and alerting setup

## Common Patterns and Examples

### Pattern 1: Single Service Application

**Original:**
```yaml
services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
```

**Transformed:**
```yaml
x-omnistrate-service-plan:
  name: "web-service-plan"
  tenancyType: "OMNISTRATE_DEDICATED_TENANCY"
  deployment:
    hostedDeployment:
      AwsAccountId: "123456789"

services:
  web:
    image: nginx:latest
    x-omnistrate-mode-internal: false  # Single service = root
    x-omnistrate-compute:
      instanceTypes:
        - cloudProvider: aws
          name: t3.small
    ports:
      - "80:80"
```

### Pattern 2: Database + Application

**Transformed structure:**
```yaml
services:
  app:  # Root service
    image: omnistrate/noop
    x-omnistrate-mode-internal: false
    depends_on:
      - web
      - database
    x-omnistrate-api-params:
      - key: dbPassword
        type: Password
        parameterDependencyMap:
          database: dbPassword
    x-omnistrate-capabilities:
      backupConfiguration:
        backupRetentionInDays: 7

  web:
    x-omnistrate-mode-internal: true
    # ... config

  database:
    x-omnistrate-mode-internal: true
    x-omnistrate-api-params:
      - key: dbPassword
        type: Password
    environment:
      - POSTGRES_PASSWORD=$var.dbPassword
    # ... config
```

### Pattern 3: Service with Autoscaling

```yaml
services:
  api:
    x-omnistrate-compute:
      instanceTypes:
        - cloudProvider: gcp
          name: e2-standard-2
    x-omnistrate-capabilities:
      autoscalingConfig:
        minReplicas: 2
        maxReplicas: 10
        targetCPUUtilization: 75
```

## Troubleshooting Guide

### Issue: "Parameter not found"
**Cause:** Using `$var.X` without defining API parameter
**Fix:** Add parameter to `x-omnistrate-api-params`

### Issue: "Cloud account not found"
**Cause:** Invalid account ID or ARN
**Fix:** Run `mcp__ctl__account_describe` and copy exact values

### Issue: "Service failed to start"
**Cause:** Health check failing or startup timeout
**Fix:** Check logs with workflow events, increase timeout, or adjust health check

### Issue: "Volume mount failed"
**Cause:** Invalid storage type or size
**Fix:** Verify storage type is valid for cloud and instance type

### Issue: "Build validation error"
**Cause:** Invalid YAML syntax or missing required fields
**Fix:** Get JSON schema with `json_schema_only` flag and validate

## Best Practices

1. **Start simple** - Get basic deployment working before adding features
2. **Test incrementally** - Build and deploy after each major change
3. **Use version control** - Track changes to compose spec
4. **Document parameters** - Clear descriptions help customers
5. **Plan for scale** - Consider autoscaling from the start
6. **Enable observability** - Always add logging and metrics integrations
7. **Backup stateful services** - Configure backups for databases
8. **Search docs** - Always verify extension syntax before use
9. **Never guess** - If unsure about a feature or syntax, search docs or skip it
10. **Be explicit about gaps** - Document any transformations you skipped due to uncertainty

## Getting Help

1. **Documentation:** Use `mcp__ctl__docs_compose_spec_search`
2. **JSON Schemas:** Add `json_schema_only=true` to see full schema
3. **Support:** Contact support@omnistrate.com for undocumented features
4. **Community:** Join Omnistrate community for examples and patterns

## Success Criteria

Your service is ready when:
- ✅ Build succeeds without validation errors
- ✅ **Test instance deploys successfully and reaches RUNNING status**
- ✅ **All resources are healthy (not FAILED or stuck in DEPLOYING)**
- ✅ All health checks pass
- ✅ Customer parameters work as expected
- ✅ Backups configured for stateful services (if applicable)
- ✅ Multiple instances can run concurrently
- ✅ Monitoring and logging are functional
- ✅ All transformations are based on verified documentation
- ✅ Any skipped features are clearly documented with reasons
- ✅ **You have iterated through at least one full deploy-debug-fix cycle**

## When to Skip Features

**Skip and document when:**
1. Documentation search returns no results
2. Feature syntax is ambiguous or unclear
3. You're not confident the transformation is correct
4. The feature is not critical for basic functionality
5. Conflicting information exists in documentation

**How to document skipped features:**
```markdown
## Skipped Transformations

1. **Advanced metrics configuration** - Documentation unclear on x-<vendor>Metrics syntax for this use case
2. **Custom health checks** - Unsure of correct ActionHook type for this specific scenario
3. **Multi-zone deployment** - Insufficient information on enableMultiZone requirements
```

**Remember:** A working basic service is better than a broken advanced one. Start simple, validate, then iterate to add complexity.
