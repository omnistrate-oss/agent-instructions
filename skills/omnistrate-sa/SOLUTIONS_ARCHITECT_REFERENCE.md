# Omnistrate Solutions Architect Reference

This document provides detailed reference material for architecting SaaS solutions on Omnistrate.

## Table of Contents
1. [Compose Spec Extensions Reference](#compose-spec-extensions-reference)
2. [API Parameter Types & Configuration](#api-parameter-types--configuration)
3. [System Parameters Catalog](#system-parameters-catalog)
4. [Multi-Cloud Resource Sizing](#multi-cloud-resource-sizing)
5. [Integration Patterns](#integration-patterns)
6. [Architecture Decision Framework](#architecture-decision-framework)
7. [Production Readiness Checklist](#production-readiness-checklist)

---

## Compose Spec Extensions Reference

### Core Extensions

#### x-omnistrate-integrations
**Purpose**: Define service plans and cloud account mappings
**Location**: Top-level in compose file
**Required**: Yes

```yaml
x-omnistrate-integrations:
  - serviceId: <uuid>
    serviceEnvironmentId: <uuid>
    serviceModelId: <uuid>
    servicePlans:
      - planName: free
        cloudProviders:
          - cloudProvider: aws
            cloudProviderAccountId: "123456789012"
            cloudAccountBootstrapRoleARN: "arn:aws:iam::123456789012:role/OmnistrateBootstrap"
            cloudRegions:
              - region: us-west-2
          - cloudProvider: gcp
            cloudProviderProjectId: "project-id"
            cloudProviderServiceAccountEmail: "sa@project.iam.gserviceaccount.com"
            cloudRegions:
              - region: us-central1
```

#### x-omnistrate-mode-internal
**Purpose**: Mark service as internal (child) or external (root)
**Location**: Service level
**Values**: `true` (internal) or `false` (external/root)

```yaml
services:
  app:
    x-omnistrate-mode-internal: false  # Root service
  database:
    x-omnistrate-mode-internal: true   # Child service
```

#### x-omnistrate-api-params
**Purpose**: Define customer-facing configuration parameters
**Location**: Service level (typically on root service)
**Documentation**: Always search with `mcp__ctl__docs_compose_spec_search query="x-omnistrate-api-params"`

```yaml
x-omnistrate-api-params:
  - key: instanceType
    name: Instance Type
    description: Compute instance size
    type: String
    modifiable: true
    required: true
    defaultValue: t3.medium
    uiGroup: Compute
    parameterDependencyMap:
      backend: instanceType  # Flow to child service

  - key: adminPassword
    name: Admin Password
    description: Administrator password
    type: Password  # Masked in UI
    modifiable: false
    required: true
```

**Parameter Properties**:
- `key`: Unique identifier (used in $var references)
- `name`: Display name in UI
- `description`: Help text for users
- `type`: Boolean, String, Password, Float64, Int, Bytes, JSON, Resource
- `modifiable`: Can user change after creation?
- `required`: Must user provide value?
- `defaultValue`: Pre-populated value
- `allowedValues`: Dropdown options
- `regex`: Input validation pattern
- `minValue`/`maxValue`: Numeric bounds
- `uiGroup`: Group related parameters in UI
- `parameterDependencyMap`: Flow to child services

#### x-omnistrate-compute
**Purpose**: Configure compute resources (instance types, replicas)
**Location**: Service level
**Documentation**: `mcp__ctl__docs_compose_spec_search query="x-omnistrate-compute"`

```yaml
x-omnistrate-compute:
  replicaCount:
    value: 3  # Fixed count
    # OR
    apiParam: replicaCount  # Dynamic via parameter

  instanceTypes:
    - cloudProvider: aws
      apiParam: instanceType  # Customer selects
      # OR
      minCloudInstanceType: t3.medium  # System selects >= this
      # OR
      preferredCloudInstanceType: t3.large  # System tries this first

    - cloudProvider: gcp
      apiParam: gcpInstanceType

    - cloudProvider: azure
      apiParam: azureInstanceType
```

**Instance Type Strategies**:
- `apiParam`: Customer controls exact type (max flexibility)
- `minCloudInstanceType`: System auto-selects >= specified (simplicity)
- `preferredCloudInstanceType`: System tries this, falls back if unavailable (balance)

#### x-omnistrate-storage
**Purpose**: Configure persistent volumes
**Location**: Service level (on services needing storage)
**Documentation**: `mcp__ctl__docs_compose_spec_search query="x-omnistrate-storage"`

```yaml
x-omnistrate-storage:
  - path: /var/lib/postgresql/data
    size: 100Gi
    # OR
    sizeAPIParam: storageSize  # Dynamic sizing

    storageClass: standard  # Or premium-ssd
    cloudProvider: aws
    awsEbsVolumeType: gp3  # gp2, gp3, io1, io2
    awsEbsIops: 3000       # For io1/io2

  - path: /data/cache
    size: 50Gi
    cloudProvider: gcp
    gcpPersistentDiskType: pd-ssd  # pd-standard, pd-ssd, pd-extreme
```

**Storage Type Selection**:
- **Standard (gp2/pd-standard)**: Cost-effective, general workloads
- **Balanced (gp3/pd-balanced)**: Better price/performance
- **High Performance (io2/pd-ssd)**: Databases, low-latency needs
- **Extreme (pd-extreme)**: Ultra-high IOPS requirements

#### x-omnistrate-capabilities
**Purpose**: Enable advanced features (backups, autoscaling, HA)
**Location**: Service level (only on root services)
**Documentation**: `mcp__ctl__docs_compose_spec_search query="x-omnistrate-capabilities"`

```yaml
x-omnistrate-capabilities:
  # Backup configuration
  backupConfiguration:
    - cloudProvider: aws
      name: nightly
      cronExpression: "0 2 * * *"  # 2 AM daily
      type: aws-ebs-snapshot
      retentionDays: 7
      backupKeyValueMap:
        volumePath: /data

  # Autoscaling
  autoscaling:
    - metric: CpuMetric  # Or MemoryMetric, custom metrics
      targetValue: 70    # Target CPU %
      minReplicas: 2
      maxReplicas: 10

  # High availability
  enableMultiZone: true  # Deploy across AZs
```

**Backup Types by Cloud**:
- AWS: `aws-ebs-snapshot`
- GCP: `gcp-persistent-disk-snapshot`
- Azure: `azure-managed-disk-snapshot`

#### x-omnistrate-actionhooks
**Purpose**: Custom logic at lifecycle events
**Location**: Service level
**Documentation**: `mcp__ctl__docs_compose_spec_search query="x-omnistrate-actionhooks"`

```yaml
x-omnistrate-actionhooks:
  - scope: CLUSTER  # Or NODE
    type: INIT  # When: First deployment
    commandTemplate: |
      echo "Initializing cluster..."
      psql -c "CREATE EXTENSION pg_stat_statements;"

  - scope: NODE
    type: POST_START  # After node starts
    commandTemplate: |
      curl -X POST http://control-plane/register?node=$sys.compute.node.nodeId

  - scope: CLUSTER
    type: HEALTH_CHECK  # Custom health check
    commandTemplate: |
      curl -f http://localhost:8080/health || exit 1
```

**Hook Types**:
- **CLUSTER scope**: INIT, POST_START, PRE_STOP, POST_UPGRADE, PRE_UPGRADE
- **NODE scope**: INIT, POST_START, PRE_START, HEALTH_CHECK, READINESS_CHECK, STARTUP_CHECK, ADD_NODE, REMOVE_NODE, PROMOTE, DEMOTE

#### x-omnistrate-integrations (Load Balancer)
**Purpose**: Configure load balancers for services with multiple replicas
**Location**: Service level
**Note**: Only needed when replicas > 1

```yaml
x-omnistrate-integrations:
  loadBalancer:
    - cloudProvider: aws
      type: layer7  # HTTP/HTTPS path-based routing
      port: 8080
      healthCheckPath: /health
      healthCheckProtocol: HTTP
      healthCheckInterval: 30
      healthCheckTimeout: 5
      healthyThreshold: 2
      unhealthyThreshold: 3

    - cloudProvider: gcp
      type: layer4  # TCP port-based
      port: 5432
```

**Load Balancer Types**:
- **Layer 4 (TCP)**: Port-based routing, databases, generic TCP services
- **Layer 7 (HTTP)**: Path-based routing, web apps, REST APIs

### Internal Integration Extensions

#### x-internal-integrations
**Purpose**: Configure provider-side integrations (metrics, logs, metering)
**Location**: Top-level or service level

```yaml
x-internal-integrations:
  # Observability
  metrics:
    provider: newRelic  # Or datadog, signoz, omnistrate, custom
    endpoint: https://otlp.nr-data.net
    secretLocators:
      aws: arn:aws:secretsmanager:us-west-2:123456789012:secret:newrelic-key
      gcp: projects/123/secrets/newrelic-key/versions/latest

  logs:
    provider: datadog
    endpoint: https://http-intake.logs.datadoghq.com
    secretLocators:
      aws: arn:aws:secretsmanager:us-west-2:123456789012:secret:datadog-key

  # Metering
  metering:
    enabled: true
    metrics:
      - name: storage_gb_hours
        type: gauge
        path: /var/lib/data
      - name: api_requests
        type: counter
      - name: compute_hours
        type: counter
```

---

## API Parameter Types & Configuration

### Parameter Types

#### Boolean
```yaml
- key: enableSSL
  type: Boolean
  defaultValue: true
```

#### String
```yaml
- key: databaseName
  type: String
  defaultValue: myapp
  regex: ^[a-z][a-z0-9_]{2,62}$  # Validation
```

#### Password
```yaml
- key: adminPassword
  type: Password
  required: true
  # Masked in UI, encrypted in storage
```

#### Float64
```yaml
- key: cacheSize
  type: Float64
  defaultValue: 2.5
  minValue: 1.0
  maxValue: 100.0
```

#### Int
```yaml
- key: maxConnections
  type: Int
  defaultValue: 100
  minValue: 10
  maxValue: 1000
```

#### Bytes (human-readable sizes)
```yaml
- key: memoryLimit
  type: Bytes
  defaultValue: 2Gi
  # User enters: 512Mi, 2Gi, etc.
```

#### JSON
```yaml
- key: customConfig
  type: JSON
  defaultValue: '{"feature": "enabled"}'
```

#### Resource (for resource linking)
```yaml
- key: primaryDatabase
  type: Resource
  resourceType: postgres
  # User selects existing postgres instance
```

### Parameter Flows

#### Pattern 1: Root to Child (Environment Variables)
```yaml
# Root service
services:
  app:
    x-omnistrate-mode-internal: false
    x-omnistrate-api-params:
      - key: appPort
        type: Int
        defaultValue: 8080
        parameterDependencyMap:
          backend: appPort  # Flow to backend service

# Child service
  backend:
    x-omnistrate-mode-internal: true
    environment:
      - PORT=$var.appPort  # Receives from root
```

#### Pattern 2: Dual Definition (Compute/Storage)
```yaml
# Root service
services:
  app:
    x-omnistrate-api-params:
      - key: instanceType
        type: String
        allowedValues: [t3.medium, t3.large, t3.xlarge]
        parameterDependencyMap:
          backend: instanceType

# Child service (MUST redefine)
  backend:
    x-omnistrate-api-params:
      - key: instanceType
    x-omnistrate-compute:
      instanceTypes:
        - cloudProvider: aws
          apiParam: instanceType
```

#### Pattern 3: Cross-Service References
```yaml
services:
  app:
    depends_on:
      - database  # Required
    environment:
      - DB_HOST="${database.sys.network.externalClusterEndpoint}"
      - DB_PORT="5432"
      - DB_USER="${database.var.dbUsername}"  # From database's parameters
```

---

## System Parameters Catalog

**Always verify with**: `mcp__ctl__docs_system_parameters`

### Network Parameters

```yaml
# Single node endpoint (for services without load balancer)
$sys.network.node.externalEndpoint  # e.g., 54.123.45.67

# Cluster endpoint (for services with load balancer)
$sys.network.externalClusterEndpoint  # e.g., lb-xyz.elb.amazonaws.com

# Internal endpoints
$sys.network.node.internalEndpoint  # e.g., 10.0.1.5
$sys.network.internalClusterEndpoint  # e.g., service.namespace.svc.cluster.local
```

**Usage**:
```yaml
environment:
  - API_URL="{{ $sys.network.node.externalEndpoint }}:8080"
  - CLUSTER_URL="https://{{ $sys.network.externalClusterEndpoint }}"
```

### Deployment Cell Parameters

```yaml
$sys.deploymentCell.cloudProviderName  # aws, gcp, azure
$sys.deploymentCell.region             # us-west-2, us-central1, etc.
$sys.deploymentCell.accountId          # Cloud account ID
$sys.deploymentCell.oidcIssuerID       # For IRSA/Workload Identity
```

**Usage**:
```yaml
environment:
  - CLOUD_PROVIDER="${sys.deploymentCell.cloudProviderName}"
  - DEPLOYMENT_REGION="${sys.deploymentCell.region}"
```

### Compute Parameters

```yaml
$sys.compute.node.nodeId        # Unique node identifier
$sys.compute.node.nodeName      # Node name in cluster
$sys.compute.instanceType       # Actual instance type deployed
```

### Storage Parameters

```yaml
$sys.storage.volumeId           # Cloud volume identifier
$sys.storage.bucket.name        # Object storage bucket name
```

### Instance Parameters

```yaml
$sys.instance.id                # Omnistrate instance ID
$sys.instance.name              # User-provided instance name
$sys.resource.id                # Resource ID
$sys.resource.key               # Resource key
```

---

## Multi-Cloud Resource Sizing

### Compute Instance Mapping

#### General Purpose (Balanced CPU/Memory)
| AWS | GCP | Azure | vCPU | Memory | Use Case |
|-----|-----|-------|------|--------|----------|
| t3.medium | e2-medium | B2s | 2 | 4 GB | Dev/test, low traffic |
| t3.large | e2-standard-2 | B2ms | 2 | 8 GB | Small apps |
| t3.xlarge | e2-standard-4 | B4ms | 4 | 16 GB | Medium apps |
| m5.large | n2-standard-2 | D2s_v3 | 2 | 8 GB | Production apps |
| m5.xlarge | n2-standard-4 | D4s_v3 | 4 | 16 GB | Standard workloads |
| m5.2xlarge | n2-standard-8 | D8s_v3 | 8 | 32 GB | High traffic apps |

#### Compute Optimized (High CPU)
| AWS | GCP | Azure | vCPU | Memory | Use Case |
|-----|-----|-------|------|--------|----------|
| c5.large | c2-standard-4 | F2s_v2 | 2 | 4 GB | CPU-intensive |
| c5.xlarge | c2-standard-8 | F4s_v2 | 4 | 8 GB | API servers |
| c5.2xlarge | c2-standard-16 | F8s_v2 | 8 | 16 GB | High-throughput |

#### Memory Optimized (High Memory)
| AWS | GCP | Azure | vCPU | Memory | Use Case |
|-----|-----|-------|------|--------|----------|
| r5.large | n2-highmem-2 | E2s_v3 | 2 | 16 GB | Cache, small DB |
| r5.xlarge | n2-highmem-4 | E4s_v3 | 4 | 32 GB | Databases |
| r5.2xlarge | n2-highmem-8 | E8s_v3 | 8 | 64 GB | Large databases |
| r5.4xlarge | n2-highmem-16 | E16s_v3 | 16 | 128 GB | In-memory DB |

#### GPU Instances (AI/ML)
| AWS | GCP | Azure | GPU | Use Case |
|-----|-----|-------|-----|----------|
| g4dn.xlarge | n1-standard-4-t4 | NC4as_T4_v3 | T4 | Inference |
| p3.2xlarge | n1-standard-8-v100 | NC6s_v3 | V100 | Training |
| p4d.24xlarge | a2-highgpu-8g | ND96asr_v4 | A100 | Large models |

### Storage Sizing

#### Performance Tiers
| Tier | AWS | GCP | Azure | IOPS | Use Case |
|------|-----|-----|-------|------|----------|
| Standard | gp2 | pd-standard | Standard SSD | 3-16K | General |
| Balanced | gp3 | pd-balanced | Premium SSD | 3-16K | Most workloads |
| High Perf | io2 | pd-ssd | Ultra SSD | 16K-256K | Databases |
| Extreme | io2 Block Express | pd-extreme | Ultra SSD | 256K+ | Extreme IOPS |

#### Size Recommendations by Workload
- **Small App**: 20-50 GB (logs, configs)
- **Medium App**: 50-100 GB (application data)
- **Small Database**: 100-250 GB (PostgreSQL, MySQL)
- **Medium Database**: 250-500 GB (Production DB)
- **Large Database**: 500+ GB (High-volume DB)
- **Data Lake**: 1+ TB (Analytics, archives)

---

## Integration Patterns

### Observability Integration

#### Pattern 1: NewRelic (Provider-Side)
```yaml
x-internal-integrations:
  metrics:
    provider: newRelic
    endpoint: https://otlp.nr-data.net
    secretLocators:
      aws: arn:aws:secretsmanager:us-west-2:123456789012:secret:newrelic-key
      gcp: projects/my-project/secrets/newrelic-key/versions/latest
```

#### Pattern 2: Datadog (Provider-Side)
```yaml
x-internal-integrations:
  metrics:
    provider: datadog
    endpoint: https://api.datadoghq.com
    secretLocators:
      aws: arn:aws:secretsmanager:us-west-2:123456789012:secret:datadog-key
  logs:
    provider: datadog
    endpoint: https://http-intake.logs.datadoghq.com
    secretLocators:
      aws: arn:aws:secretsmanager:us-west-2:123456789012:secret:datadog-key
```

#### Pattern 3: Omnistrate Native
```yaml
x-internal-integrations:
  metrics:
    provider: omnistrate
  logs:
    provider: omnistrate
```

### Metering Integration

```yaml
x-internal-integrations:
  metering:
    enabled: true
    metrics:
      # Storage usage
      - name: storage_gb_hours
        type: gauge
        path: /var/lib/data

      # API request count
      - name: api_requests
        type: counter

      # Compute time
      - name: compute_hours
        type: counter

      # Custom metric from application
      - name: documents_processed
        type: counter
        endpoint: http://localhost:8080/metrics
```

### Billing Integration

```yaml
x-omnistrate-integrations:
  billing:
    provider: stripe
    secretLocator: arn:aws:secretsmanager:region:account:secret:stripe-key
    plans:
      - planName: pro
        priceId: price_xxxxx
        billingCycle: monthly
```

### Marketplace Integration

#### AWS Marketplace
```yaml
x-omnistrate-integrations:
  marketplace:
    - provider: aws
      productCode: prod-xxxxx
      meteringDimensions:
        - name: instance-hours
          meteringKey: compute_hours
```

#### GCP Marketplace
```yaml
x-omnistrate-integrations:
  marketplace:
    - provider: gcp
      planId: my-saas-plan
      meteringMetrics:
        - name: api-calls
          meteringKey: api_requests
```

---

## Architecture Decision Framework

### Decision 1: Single vs Multi-Service Architecture

**Choose Single Service When**:
- Application is monolithic (single container)
- No inter-service dependencies
- Simple deployment model
- Example: Static website, simple API server

**Choose Multi-Service When**:
- Microservices architecture
- Multiple containers with dependencies
- Need independent scaling per service
- Example: Web + App + Database + Cache

**Implementation**:
```yaml
# Single Service
services:
  app:
    x-omnistrate-mode-internal: false  # This is the root

# Multi-Service
services:
  root:  # Synthetic orchestrator
    image: omnistrate/noop
    x-omnistrate-mode-internal: false
    depends_on: [web, app, db]

  web:
    x-omnistrate-mode-internal: true
  app:
    x-omnistrate-mode-internal: true
  db:
    x-omnistrate-mode-internal: true
```

### Decision 2: Deployment Model Selection

| Factor | SaaS Provider | BYOC | BYOC Copilot | On-Premise |
|--------|---------------|------|--------------|------------|
| **Security** | Medium | High | Highest | Highest |
| **Customer Control** | Low | High | High | Highest |
| **Management Burden** | Provider | Provider | Provider | Customer |
| **Setup Complexity** | Low | Medium | Medium | High |
| **Cost Model** | Subscription | Subscription | Subscription | License |
| **Use Case** | Most SaaS | Enterprise | Max Security | Regulated |

**Architecture Pattern**: Support multiple models in same service
```yaml
x-omnistrate-integrations:
  - servicePlans:
      - planName: starter
        deploymentModel: saas
      - planName: enterprise
        deploymentModel: byoc
```

### Decision 3: Storage Architecture

**Ephemeral Storage** (No volumes):
- Stateless applications
- Cache that can be rebuilt
- Temporary processing data

**Persistent Storage** (Volumes):
- Databases
- User-uploaded content
- Application state that must survive restarts

**Object Storage** (S3/GCS):
- Media files
- Backups
- Data archives
- ML model storage

### Decision 4: Scaling Strategy

**No Scaling** (Fixed replicas):
```yaml
x-omnistrate-compute:
  replicaCount:
    value: 1  # Or 2, 3, etc.
```
- Use for: Databases, stateful services, low-traffic apps

**Manual Scaling** (User-controlled):
```yaml
x-omnistrate-compute:
  replicaCount:
    apiParam: replicaCount
```
- Use for: Predictable traffic, cost control, simple deployments

**Autoscaling** (Automatic):
```yaml
x-omnistrate-capabilities:
  autoscaling:
    - metric: CpuMetric
      targetValue: 70
      minReplicas: 2
      maxReplicas: 10
```
- Use for: Variable traffic, web apps, APIs, SaaS products

### Decision 5: High Availability Strategy

**Basic** (Single zone, no HA):
- Free tier / dev environments
- Non-critical applications
- Cost-sensitive deployments

**Standard** (Multi-zone):
```yaml
x-omnistrate-capabilities:
  enableMultiZone: true
```
- Production applications
- SLA requirements
- Pro/Business tiers

**Advanced** (Multi-region):
- Configure multiple deployment cells across regions
- Active-active or active-passive
- Enterprise tier
- Global applications

### Decision 6: Backup Strategy

**No Backups**:
- Free tier
- Ephemeral data
- Data recreatable from source

**Scheduled Backups**:
```yaml
x-omnistrate-capabilities:
  backupConfiguration:
    - cronExpression: "0 2 * * *"  # Daily at 2 AM
      retentionDays: 7
```
- Pro tier
- Standard production apps

**Continuous Backups**:
```yaml
x-omnistrate-capabilities:
  backupConfiguration:
    - cronExpression: "0 */6 * * *"  # Every 6 hours
      retentionDays: 30
```
- Enterprise tier
- Critical data
- Compliance requirements

---

## Production Readiness Checklist

### Security
- [ ] All credentials use password-type API parameters
- [ ] Secrets stored in cloud secret managers (AWS Secrets Manager, etc.)
- [ ] IAM roles configured (no static cloud credentials)
- [ ] Network isolation configured (VPC, security groups)
- [ ] TLS/SSL enabled for all external endpoints
- [ ] API authentication implemented
- [ ] Least privilege access for service accounts
- [ ] Security scanning in CI/CD pipeline

### Reliability
- [ ] Health checks configured (liveness, readiness, startup)
- [ ] Resource limits set (CPU, memory)
- [ ] Multi-zone deployment enabled (for production)
- [ ] Graceful shutdown implemented (PreStop hooks)
- [ ] Retry logic for external dependencies
- [ ] Circuit breakers for service calls
- [ ] Timeout configurations appropriate
- [ ] Database connection pooling configured

### Observability
- [ ] Metrics integration configured (NewRelic, Datadog, etc.)
- [ ] Logging integration configured
- [ ] Custom application metrics exposed
- [ ] Alerting rules defined
- [ ] Dashboards created for key metrics
- [ ] Log retention policy set
- [ ] Tracing implemented (for distributed systems)
- [ ] Error tracking configured (Sentry, etc.)

### Scalability
- [ ] Autoscaling configured (if applicable)
- [ ] Appropriate min/max replica bounds set
- [ ] Resource sizing validated under load
- [ ] Database scaling strategy defined
- [ ] Connection pooling configured
- [ ] Caching layer implemented (if needed)
- [ ] Load balancer configured (for replicas > 1)
- [ ] Rate limiting implemented

### Data Management
- [ ] Backup schedule configured
- [ ] Backup retention policy defined
- [ ] Restore procedure tested
- [ ] Data migration strategy documented
- [ ] Storage sizing validated
- [ ] Storage performance tier appropriate
- [ ] Data encryption at rest enabled
- [ ] Disaster recovery plan documented

### Operational Excellence
- [ ] Runbooks documented for common scenarios
- [ ] On-call rotation defined
- [ ] Incident response procedures documented
- [ ] Deployment process automated
- [ ] Rollback procedure tested
- [ ] Upgrade path validated
- [ ] Monitoring alerts configured
- [ ] SLA/SLO defined and tracked

### Testing
- [ ] Deployed successfully on all target clouds (AWS, GCP, Azure)
- [ ] All service plan tiers tested
- [ ] Scaling tested (manual and autoscaling)
- [ ] Backup and restore tested
- [ ] Upgrade path tested
- [ ] Load testing completed
- [ ] Security testing completed
- [ ] Multi-zone failover tested

### Documentation
- [ ] Architecture diagram created
- [ ] Service plan features documented
- [ ] API parameters documented for customers
- [ ] Deployment models explained
- [ ] Troubleshooting guide created
- [ ] Customer onboarding guide written
- [ ] Operational runbooks completed
- [ ] Change log maintained

### Cost Optimization
- [ ] Right-sized default instance types
- [ ] Storage tier appropriate for workload
- [ ] Autoscaling bounds prevent runaway costs
- [ ] Reserved instances considered (for stable workloads)
- [ ] Spot instances used where appropriate
- [ ] Unused resources cleaned up automatically
- [ ] Cost monitoring and alerting configured
- [ ] Usage-based billing configured fairly

---

## Common Architecture Patterns

### Pattern 1: Stateless Web Application
```yaml
services:
  web:
    image: my-webapp
    x-omnistrate-mode-internal: false
    x-omnistrate-api-params:
      - key: instanceType
      - key: minReplicas
      - key: maxReplicas
    x-omnistrate-compute:
      replicaCount:
        apiParam: minReplicas
      instanceTypes:
        - cloudProvider: aws
          apiParam: instanceType
    x-omnistrate-capabilities:
      autoscaling:
        - metric: CpuMetric
          targetValue: 70
          minReplicas: 2
          maxReplicas: 10
      enableMultiZone: true
```

### Pattern 2: Three-Tier Application (Web + App + DB)
```yaml
services:
  root:
    image: omnistrate/noop
    x-omnistrate-mode-internal: false
    depends_on: [web, app, database]
    x-omnistrate-api-params: [...]
    x-omnistrate-capabilities:
      backupConfiguration: [...]

  web:
    image: nginx
    x-omnistrate-mode-internal: true
    x-omnistrate-compute:
      replicaCount: {value: 2}

  app:
    image: my-app
    x-omnistrate-mode-internal: true
    depends_on: [database]
    x-omnistrate-compute:
      replicaCount: {apiParam: appReplicas}
    x-omnistrate-capabilities:
      autoscaling: [...]

  database:
    image: postgres:14
    x-omnistrate-mode-internal: true
    x-omnistrate-storage: [...]
```

### Pattern 3: Microservices with Shared Database
```yaml
services:
  root:
    image: omnistrate/noop
    x-omnistrate-mode-internal: false
    depends_on: [api, worker, database]

  api:
    x-omnistrate-mode-internal: true
    depends_on: [database]
    environment:
      - DB_HOST="${database.sys.network.internalClusterEndpoint}"

  worker:
    x-omnistrate-mode-internal: true
    depends_on: [database]
    environment:
      - DB_HOST="${database.sys.network.internalClusterEndpoint}"

  database:
    x-omnistrate-mode-internal: true
```

### Pattern 4: Data Pipeline (Streaming)
```yaml
services:
  root:
    image: omnistrate/noop
    x-omnistrate-mode-internal: false
    depends_on: [ingress, processor, queue, storage]

  ingress:
    x-omnistrate-mode-internal: true
    x-omnistrate-compute:
      replicaCount: {apiParam: ingressReplicas}
    depends_on: [queue]

  processor:
    x-omnistrate-mode-internal: true
    x-omnistrate-capabilities:
      autoscaling: [...]
    depends_on: [queue, storage]

  queue:
    image: kafka
    x-omnistrate-mode-internal: true
    x-omnistrate-storage: [...]

  storage:
    image: postgres
    x-omnistrate-mode-internal: true
    x-omnistrate-storage: [...]
```

---

## Quick Reference Commands

### Documentation Search
```bash
# Search compose spec extensions
mcp__ctl__docs_compose_spec_search query="x-omnistrate-compute"

# List system parameters
mcp__ctl__docs_system_parameters
```

### Account Management
```bash
# List cloud accounts
mcp__ctl__account_list

# Get account details
mcp__ctl__account_describe account-name="my-aws-account"
```

### Service Lifecycle
```bash
# Build from compose
mcp__ctl__build_compose file="docker-compose-omnistrate.yaml" service_name="myservice"

# List service plans
mcp__ctl__service_plan_list service_name="myservice"

# Create instance
mcp__ctl__instance_create service_name="myservice" plan_name="pro" ...

# Check status
mcp__ctl__instance_describe service_name="myservice" instance_id="xxx" deployment_status=true

# Get workflows
mcp__ctl__workflow_list service_name="myservice" instance_id="xxx"

# Analyze workflow events
mcp__ctl__workflow_events service_name="myservice" workflow_id="yyy"
```

### Testing Expressions
```bash
# Test evaluate expressions
omctl instance evaluate <instance-id> <resource-key> --expression "$sys.deploymentCell.cloudProviderName"
```

---

## Additional Resources

- **Omnistrate Documentation**: https://docs.omnistrate.com
- **Compose Spec Reference**: Use `mcp__ctl__docs_compose_spec_search`
- **System Parameters**: Use `mcp__ctl__docs_system_parameters`
- **FDE Skill**: See `../omnistrate-fde/` for onboarding workflows
- **SRE Skill**: See `../omnistrate-sre/` for debugging workflows
