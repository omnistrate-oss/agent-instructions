# Terraform & Kustomize Onboarding Reference

Verified against `resource-spec-samples/service-spec-kustomize-terraform.yaml`,
`resource-spec-samples/terraform-spec/`, `resource-spec-samples/terraform-private-module-spec/main.tf`,
`resource-spec-samples/e2etestv2/original/kustomize/kustomization.yaml`,
`resource-spec-samples/e2etest/kustomize/kustomization.yaml`, and the Omnistrate docs under
`docs/build-guides/terraform-*.md`, `docs/getting-started/build-from-terraform.md`, and
`docs/getting-started/build-from-kustomize.md`. When this file conflicts with the live schema
or a docs search, trust the schema/docs.

Schema pin (add as the first line of your spec for editor validation):

```yaml
# yaml-language-server: $schema=https://api.omnistrate.cloud/2022-09-01-00/schema/service-spec-schema.json
```

---

## When you are on this path

- You are provisioning cloud infrastructure (RDS, GCS buckets, SQS, etc.) via Terraform / OpenTofu.
- You are deploying Kubernetes manifests via Kustomize.
- You are combining both (Terraform produces outputs that a Kustomize or Helm consumer reads).
- Spec format: **ServicePlanSpec** (not Docker Compose).
- Build flag: `--spec-type ServicePlanSpec`.
- Tenancy handled inside your Kustomize manifests; set `tenancyType: CUSTOM_TENANCY` if required.
- Use the `omnistrate-fde` skill; call `omnistrate-sre` when an instance stays failed.

For the `deployment:` block (account IDs, `hostedDeployment` vs `byoaDeployment`, field casing,
cloud-account prerequisites) see [DEPLOYMENT_MODELS_REFERENCE.md](DEPLOYMENT_MODELS_REFERENCE.md)
([choosing a model](#choosing-a-deployment-model), [hosted](#hosted),
[BYOC customer account](#byoc-customer-cloud-account)).

---

## Terraform

### Minimal skeleton

Terraform services are almost always marked `internal: true` — they are infrastructure dependencies,
not customer-facing endpoints. Copied and adapted from `resource-spec-samples/service-spec-kustomize-terraform.yaml`.

```yaml
name: Multiple Resources
deployment:
  hostedDeployment:               # see DEPLOYMENT_MODELS_REFERENCE.md for all models
    AwsAccountId: "<AWS_ACCOUNT_ID>"
    AwsBootstrapRoleAccountArn: "arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role"
    GcpProjectId: "<GCP_PROJECT_ID>"
    GcpProjectNumber: "<GCP_PROJECT_NUMBER>"
    GcpServiceAccountEmail: "<GCP_SA_EMAIL>"

services:
  - name: terraformChild
    internal: true
    terraformConfigurations:
      configurationPerCloudProvider:
        aws:
          terraformPath: /e2etestv2/original/terraform
          gitConfiguration:
            reference: refs/tags/v3.7.1
            repositoryUrl: https://github.com/your-org/infra-repo.git
            accessToken: <GITHUB_PAT>
          terraformExecutionIdentity: "arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-custom-terraform-execution-role"
        gcp:
          terraformPath: /e2etestv2/original/terraform
          gitConfiguration:
            reference: refs/tags/v3.7.1
            repositoryUrl: https://github.com/your-org/infra-repo.git
            accessToken: <GITHUB_PAT>
          terraformExecutionIdentity: "<GCP_SERVICE_ACCOUNT>"
```

---

### Source configuration

Two mutually exclusive source modes per cloud-provider entry:

| Mode | Fields | When to use |
|------|--------|-------------|
| Git-backed | `gitConfiguration.repositoryUrl`, `gitConfiguration.reference`, optionally `gitConfiguration.accessToken` | Production; pinned to a tag/branch in GitHub |
| Local artifact | `artifactRelativePath` (relative to `omnistrate-ctl build` CWD) | Dev/CI; upload local `.tf` files without a repo |

For local artifact, also set `terraformPath` to the subdirectory inside the uploaded content:

```yaml
terraformConfigurations:
  configurationPerCloudProvider:
    aws:
      terraformPath: /
      artifactRelativePath: terraform/aws    # relative to CWD; paths escaping workspace root are rejected
```

Use **one source mode per provider entry** — never set both `gitConfiguration` and `artifactRelativePath`.

`reference` forms: `refs/tags/v1.0.0` (pinned, recommended for prod), `refs/heads/main` (branch, use in dev only).

For private repositories, provide an `accessToken`. Use the `{{env:VAR}}` form if you prefer to keep
the token out of source-controlled spec files:

```yaml
gitConfiguration:
  reference: refs/tags/v1.0.0
  repositoryUrl: https://github.com/your-org/private-infra-repo.git
  accessToken: "{{env:GITHUB_PAT}}"
```

---

### Execution identity & IAM

Authentication is provider-specific. For AWS, GCP, Azure, and OCI, Omnistrate auto-creates the identity
during account setup; you only need to grant it the permissions your Terraform stack requires.

| Cloud | Auto-created identity | Override field |
|-------|-----------------------|----------------|
| AWS | `omnistrate-terraform-execution-role` IAM role | `terraformExecutionIdentity` (optional ARN override) |
| GCP | `omnistrate-tf-<org-id>` service account | `terraformExecutionIdentity` (optional SA email override) |
| Azure | `terraform-<org-id>-<subscription-id>` service principal | `terraformExecutionIdentity` |
| OCI | `<org-id>-terraform-user` | `terraformExecutionIdentity` |
| **Nebius** | **No auto-created identity** | **Must supply all three** |

Nebius requires three explicit fields on the `nebius` provider entry:

```yaml
configurationPerCloudProvider:
  nebius:
    terraformPath: /terraform/nebius
    serviceAccountID: serviceaccount-e00vqdp9fskhmmaan8
    publicKeyID: publickey-e00h9scsyy9mbefrjf
    privateKeyPEM: $secret.nebiusTerraformPrivateKey   # prefer $secret.<name> over inline PEM
    gitConfiguration:
      reference: refs/heads/main
      repositoryUrl: https://github.com/your-org/infra-repo.git
```

All three fields (`serviceAccountID`, `publicKeyID`, `privateKeyPEM`) are required for Nebius.

**BYOC custom policy:** for BYOC (customer-account) deployments you must declare the permissions
your Terraform stack needs so Omnistrate can generate correct customer onboarding scripts:

```yaml
features:
  CUSTOM_TERRAFORM_POLICY:
    policies:
      aws: |
        {
          "Statement": [
            {"Action": ["rds:*","s3:*"], "Effect": "Allow", "Resource": "*"}
          ]
        }
    roles:
      gcp:
        - name: roles/cloudsql.admin
      azure:
        - name: "Storage Account Contributor"
    permissions:
      oci:
        - "manage queues"
```

---

### State management

Omnistrate manages Terraform state automatically per deployment using Kubernetes secrets.
**Never author a `backend` block** in your `.tf` files — Omnistrate strips any custom backend
configuration and replaces it with its own managed backend. State is isolated per tenant deployment.

Lifecycle mapping:

| Customer action | Terraform operation |
|-----------------|---------------------|
| Create instance | `terraform apply` |
| Modify instance | `terraform apply` (with updated vars) |
| Delete instance | `terraform destroy` |

---

### Templating inside .tf files

Wrap Omnistrate parameters in `{{ }}` directly inside `.tf` files. Copied from
`resource-spec-samples/terraform-spec/main.tf` and `docs/build-guides/terraform-params-outputs.md`:

```hcl
provider "aws" {
  region = "{{ $sys.deploymentCell.region }}"
}

resource "aws_security_group" "app_sg" {
  name   = "app-sg-{{ $sys.id }}"
  vpc_id = "{{ $sys.deploymentCell.cloudProviderNetworkID }}"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["{{ $sys.deploymentCell.cidrRange }}"]
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "db-subnet-{{ $sys.id }}"
  subnet_ids = [
    "{{ $sys.deploymentCell.privateSubnetIDs[0].id }}",
    "{{ $sys.deploymentCell.privateSubnetIDs[1].id }}"
  ]
}
```

Common system parameters in Terraform templates:

| Parameter | Description |
|-----------|-------------|
| `$sys.id` | Unique deployment identifier — use for resource naming to avoid collisions |
| `$sys.deploymentCell.region` | Target deployment region |
| `$sys.deploymentCell.cloudProviderNetworkID` | VPC / VNet / Network ID |
| `$sys.deploymentCell.cidrRange` | CIDR range of the deployment cell |
| `$sys.deploymentCell.publicSubnetIDs[i].id` | Public subnet IDs |
| `$sys.deploymentCell.privateSubnetIDs[i].id` | Private subnet IDs |

For API parameters, use `$var.<key>` inside `{{ }}` in `.tf` files or in `variablesValuesFileOverride`.

**`variablesValuesFileOverride`** — inject `.tfvars`-format content directly from the Plan spec
(no separate `.tfvars` file needed in the repo). Copied from `docs/build-guides/terraform-params-outputs.md`:

```yaml
services:
  - name: dbInfra
    internal: true
    apiParameters:
      - key: dbInstanceClass
        description: Database instance class
        name: Database Instance Class
        type: String
        modifiable: true
        required: false
        export: false
        defaultValue: "db.t3.medium"
    terraformConfigurations:
      configurationPerCloudProvider:
        aws:
          terraformPath: /terraform/aws
          variablesValuesFileOverride: |
            vpc_id = "{{ $sys.deploymentCell.cloudProviderNetworkID }}"
            region = "{{ $sys.deploymentCell.region }}"
            instance_type = "{{ $var.dbInstanceClass }}"
            subnet_ids = [
              "{{ $sys.deploymentCell.privateSubnetIDs[0].id }}",
              "{{ $sys.deploymentCell.privateSubnetIDs[1].id }}"
            ]
            resource_prefix = "saas-{{ $sys.id }}"
          gitConfiguration:
            reference: refs/tags/v1.0.0
            repositoryUrl: https://github.com/your-org/infra-repo.git
```

Alternatively, declare the variable's default directly in `variables.tf`. Copied from
`resource-spec-samples/terraform-spec/variables.tf`:

```hcl
variable "region" {
  description = "The region in which the resources will be created"
  type        = string
  default     = "{{ $sys.deploymentCell.region }}"
}
```

---

### Private modules

Use the `$sys.deployment.terraformPrivateModuleGitAccessTokens.token` system parameter to inject
a Git access token into private module sources. Copied verbatim from
`resource-spec-samples/terraform-private-module-spec/main.tf`:

```hcl
module "ec2_instance" {
  source = "git::https://{{ $sys.deployment.terraformPrivateModuleGitAccessTokens.token }}@github.com/terraform-aws-modules/terraform-aws-ec2-instance"

  instance_type = "t2.micro"
}
```

Configure the token in your account settings; Omnistrate resolves `$sys.deployment.terraformPrivateModuleGitAccessTokens.token`
at plan time.

---

### Outputs

Terraform outputs are automatically captured after every `apply`. All outputs are available to
dependent resources via `{{ $<serviceName>.out.<key> }}`. Copied from
`docs/getting-started/build-from-terraform.md`:

```hcl
# outputs.tf
output "rds_endpoints_1" {
  value = aws_db_instance.example1.endpoint
}

output "rds_endpoints_2" {
  value = {
    endpoint = aws_db_instance.example2.endpoint
  }
  sensitive = true
}

output "elasticache_endpoint" {
  value = aws_elasticache_cluster.example_memcached.cache_nodes[0].address
}
```

Consumed in a dependent resource (the service name is the root):

```yaml
# {{ $terraformChild.out.rds_endpoints_1 }}
# {{ $terraformChild.out.rds_endpoints_2.endpoint }}     ← dot-notation for nested objects
# {{ $terraformChild.out.elasticache_endpoint }}
```

The `<serviceName>` root matches the `name:` field of the Terraform service in the Plan spec.
Copied from `resource-spec-samples/e2etest/kustomize/kustomization.yaml` — note nested field:

```yaml
# e2etest pattern
- s3Bucket={{ $terraformChild.out.bucket_url.arn }}     # bucket_url is the output, .arn is the nested field
```

To make selected outputs surface as exported fields on the Terraform resource itself (visible
in the Omnistrate portal/API), declare them under `requiredOutputs`:

```yaml
terraformConfigurations:
  configurationPerCloudProvider:
    aws:
      terraformPath: /terraform/aws
      gitConfiguration:
        reference: refs/heads/main
        repositoryUrl: https://github.com/your-org/infra-repo.git
      requiredOutputs:
        - key: rds_endpoints_1
          exported: true
        - key: elasticache_endpoint
          exported: true
```

`requiredOutputs` does not replace `{{ $<serviceName>.out.<key> }}` consumption — dependent resources
always use the template syntax.

**Outputs as endpoints:** inject Terraform-produced endpoints into Helm `chartValues` or Kustomize
`configMapGenerator` literals using the same `{{ $<serviceName>.out.<key> }}` syntax.

---

### Control-plane-side resources

Some Terraform stacks manage provider-side assets (shared DNS, registry entries, cross-account
resources) that must execute in the Omnistrate control plane account rather than the customer's
deployment cell. Set `deploymentTarget.account: ControlPlane`:

```yaml
services:
  - name: controlPlaneInfra
    internal: true
    deploymentTarget:
      account: ControlPlane
    terraformConfigurations:
      configurationPerCloudProvider:
        aws:
          terraformPath: /terraform/control_plane
          gitConfiguration:
            reference: refs/heads/main
            repositoryUrl: https://github.com/your-org/infra-repo.git
```

Only define the cloud-provider entry that executes the stack — no placeholder entries for other
clouds are needed.

---

### Multi-cloud parity

Define per-cloud stacks under `configurationPerCloudProvider`. Omnistrate selects the correct entry
at deploy time based on where the instance lands. Keep output names identical across all clouds
so dependent resources need no cloud-specific branching:

```yaml
terraformConfigurations:
  configurationPerCloudProvider:
    aws:
      terraformPath: /terraform/aws
      gitConfiguration:
        reference: refs/tags/v1.0.0
        repositoryUrl: https://github.com/your-org/infra-repo.git
    gcp:
      terraformPath: /terraform/gcp
      gitConfiguration:
        reference: refs/tags/v1.0.0
        repositoryUrl: https://github.com/your-org/infra-repo.git
    azure:
      terraformPath: /terraform/azure
      gitConfiguration:
        reference: refs/tags/v1.0.0
        repositoryUrl: https://github.com/your-org/infra-repo.git
    oci:
      terraformPath: /terraform/oci
      gitConfiguration:
        reference: refs/tags/v1.0.0
        repositoryUrl: https://github.com/your-org/infra-repo.git
    nebius:
      terraformPath: /terraform/nebius
      serviceAccountID: serviceaccount-e00vqdp9fskhmmaan8
      publicKeyID: publickey-e00h9scsyy9mbefrjf
      privateKeyPEM: $secret.nebiusTerraformPrivateKey
      gitConfiguration:
        reference: refs/tags/v1.0.0
        repositoryUrl: https://github.com/your-org/infra-repo.git
```

Example of matching output names across clouds (all three output `database_endpoint`):

```hcl
# AWS outputs.tf
output "database_endpoint" { value = aws_db_instance.main.endpoint }

# GCP outputs.tf
output "database_endpoint" { value = google_sql_database_instance.main.private_ip_address }

# Azure outputs.tf
output "database_endpoint" { value = azurerm_postgresql_flexible_server.main.fqdn }
```

---

## Kustomize

### Minimal skeleton

Copied and adapted from `resource-spec-samples/service-spec-kustomize-terraform.yaml`.

```yaml
services:
  - name: kustomizeRoot
    type: kustomize
    compute:
      instanceTypes:
        - name: t4g.small
          cloudProvider: aws
        - name: e2-medium
          cloudProvider: gcp
    network:
      ports:
        - 3306
    kustomizeConfiguration:
      kustomizePath: /e2etestv2/original/kustomize
      gitConfiguration:
        reference: refs/tags/v3.7.1
        repositoryUrl: https://github.com/your-org/infra-repo.git
        accessToken: <GITHUB_PAT>
    apiParameters:
      - key: username
        description: Username
        name: Username
        type: String
        modifiable: true
        required: false
        export: true
        defaultValue: username
      - key: password
        description: Default DB Password
        name: Password
        type: String
        modifiable: false
        required: false
        export: false
        defaultValue: postgres
```

Key fields:

| Field | Required | Notes |
|-------|----------|-------|
| `type: kustomize` | Yes | Declares this service as a Kustomize deployment |
| `kustomizeConfiguration.kustomizePath` | Yes | Directory inside the repo containing `kustomization.yaml` |
| `kustomizeConfiguration.gitConfiguration` | Yes | Same sub-fields as Terraform: `repositoryUrl`, `reference`, optional `accessToken` |
| `compute.instanceTypes` | Yes | One entry per cloud provider; use `name:` for a fixed type or `apiParam:` for customer-selectable |
| `network.ports` | No | Ports to expose; required if service needs inbound connectivity |

---

### Templating kustomization.yaml

Omnistrate renders `kustomization.yaml` with the same `{{ }}` template syntax as Terraform.
Copied verbatim from `resource-spec-samples/e2etestv2/original/kustomize/kustomization.yaml`:

```yaml
resources:
  - pg.yaml
  - hpa.yaml
  - https://github.com/omnistrate/resource-spec-samples//e2etestv2/original/kustomize/config?ref=v3.7.23

namespace: "{{ $sys.id }}"

configMapGenerator:
  - name: pg-config
    literals:
      - defaultPassword=admin
      - pgDefaultUsername={{ $var.username }}
      - pgDefaultPassword={{ $var.password }}
      - dbEndpoint1={{ $terraformChild.out.db_endpoints_1 }}
      - dbEndpoint2={{ $terraformChild.out.db_endpoints_2.endpoint }}
      - redisEndpoint={{ $terraformChild2.out.redis_endpoint }}
      - pubsubId={{ $terraformChild2.out.pubsub_id }}

secretGenerator:
  - name: pg-secret
    type: Opaque
    files:
      - config.toml
```

Notes:
- `namespace: "{{ $sys.id }}"` — sets the Kubernetes namespace to the unique deployment identifier.
- `configMapGenerator` `literals` can include `$var.*` (API parameters) and `{{ $<serviceName>.out.<key> }}`
  (Terraform outputs from a `dependsOn` service).
- `secretGenerator` works as in standard Kustomize.
- Remote bases: pin with `?ref=<tag>` (e.g. `?ref=v3.7.23`) — never leave a remote base unpinned in prod.
- `$terraformChild.out.*` roots use the **service name** from `dependsOn` (e.g. `terraformChild`, `terraformChild2`).

From `resource-spec-samples/e2etest/kustomize/kustomization.yaml` — example of a nested output field:

```yaml
configMapGenerator:
  - name: pg-config
    literals:
      - s3Bucket={{ $terraformChild.out.bucket_url.arn }}   # nested: output key = bucket_url, field = .arn
```

---

### Workload manifests

Pods created by Kustomize manifests require node affinity to land on Omnistrate-managed nodes.
Copied from `docs/getting-started/build-from-kustomize.md`:

```yaml
# pg.yaml (excerpt)
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: omnistrate.com/resource
                    operator: In
                    values:
                      - '{{ $sys.deployment.resourceID }}'
      volumes:
        - name: postgres-storage
          persistentVolumeClaim:
            claimName: "{{ $sys.id }}-pvc"
```

PVC naming convention — use `{{ $sys.id }}-pvc` for per-instance isolation:

```yaml
# pgpvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: "{{ $sys.id }}-pvc"
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: omnistrate-platform-default
  resources:
    requests:
      storage: 5Gi
```

---

## Combining Terraform + Kustomize (or Helm)

The canonical pattern: Terraform provisions cloud infra (internal), Kustomize (or Helm) consumes
its outputs. Use `dependsOn` to declare the ordering. Copied from
`resource-spec-samples/service-spec-kustomize-terraform.yaml`:

```yaml
services:
  - name: terraformChild        # internal infra service
    internal: true
    terraformConfigurations:
      configurationPerCloudProvider:
        aws:
          terraformPath: /e2etestv2/original/terraform
          gitConfiguration:
            reference: refs/tags/v3.7.1
            repositoryUrl: https://github.com/your-org/infra-repo.git

  - name: terraformChild2       # second internal infra service (e.g. caching layer)
    internal: true
    terraformConfigurations:
      configurationPerCloudProvider:
        aws:
          terraformPath: /e2etestv2/original/terraform2
          gitConfiguration:
            reference: refs/tags/v3.7.1
            repositoryUrl: https://github.com/your-org/infra-repo.git

  - name: kustomizeRoot         # customer-facing Kustomize service
    type: kustomize
    dependsOn:
      - terraformChild
      - terraformChild2
    compute:
      instanceTypes:
        - name: t4g.small
          cloudProvider: aws
    network:
      ports:
        - 3306
    kustomizeConfiguration:
      kustomizePath: /e2etestv2/original/kustomize
      gitConfiguration:
        reference: refs/tags/v3.7.1
        repositoryUrl: https://github.com/your-org/infra-repo.git
```

In `kustomization.yaml`, consume Terraform outputs using the service names as roots:

```yaml
- dbEndpoint1={{ $terraformChild.out.db_endpoints_1 }}
- redisEndpoint={{ $terraformChild2.out.redis_endpoint }}
```

The same pattern applies to Helm + Terraform (replace `kustomizeConfiguration` with
`helmChartConfiguration`; see `HELM_ONBOARDING_REFERENCE.md`).

---

## Build, deploy, iterate

```bash
# Login
omnistrate-ctl login --email "$EMAIL" --password-stdin

# Build and release (idempotent — re-run after every spec edit)
omnistrate-ctl build \
  --spec-type ServicePlanSpec \
  --file spec.yaml \
  --product-name "MyTerraformKustomize" \
  --environment Dev \
  --environment-type Dev \
  --release-as-preferred

# Create instance
omnistrate-ctl instance create \
  --service "MyTerraformKustomize" \
  --plan "Multiple Resources" \
  --environment Dev \
  --cloud-provider aws \
  --region us-east-1 \
  --resource "kustomizeRoot" \
  --param '{"username":"admin","password":"secret"}' \
  --output json

# Lifecycle operations
omnistrate-ctl instance list --output json
omnistrate-ctl instance describe <instance-id> --output json
omnistrate-ctl instance stop <instance-id> --output json
omnistrate-ctl instance start <instance-id> --output json
omnistrate-ctl instance delete <instance-id> --output json

# Debug a failing instance
omnistrate-ctl instance debug <instance-id>
```

For local Terraform artifact sources, run `omnistrate-ctl build` from the workspace root that
contains the `artifactRelativePath` target.

**Debug loop:** instance describe (status) → `instance debug <id>` → fix spec → rebuild → redeploy.
For systematic debugging of failed Terraform or Kustomize deployments, call the `omnistrate-sre` skill.

**Restart vs new version:** modifying a running instance re-runs `terraform apply` with updated
variable values. A spec change (new chart version, new terraform path) requires a rebuild
(`omnistrate-ctl build`) to produce a new Plan version, then the instance modify picks up that version.

---

## Common mistakes

| Mistake | Effect | Fix |
|---------|--------|-----|
| `backend` block authored in `.tf` | Omnistrate strips it; state may be inconsistent during first apply | Remove all `backend` blocks — Omnistrate manages state |
| Unpinned git `reference` (`refs/heads/main`) in production | Non-deterministic deploys; infra changes on next apply | Pin to a tag: `refs/tags/v1.0.0` |
| Output referenced before `dependsOn` declared | Template render fails — `$serviceName` is unknown at render time | Add `dependsOn: [<terraformServiceName>]` on the consuming service |
| Missing execution-identity permissions | Terraform `apply` fails with permission denied on cloud API | Grant your Terraform stack's required IAM roles/policies to the auto-created identity (or custom role) |
| Nebius entry missing one of the three auth fields | Authentication error at plan time | All three of `serviceAccountID`, `publicKeyID`, `privateKeyPEM` are required for `nebius` |
| `$var.*` in `kustomization.yaml` not declared in `apiParameters` | Literal `{{ $var.x }}` rendered into ConfigMap | Declare every referenced key in `apiParameters` on the Kustomize service |
| Pod affinity block omitted from workload manifests | Pods may schedule onto wrong/shared nodes | Add `omnistrate.com/resource: '{{ $sys.deployment.resourceID }}'` node affinity |
| PVC name not namespaced by `$sys.id` | PVC name collisions across tenant instances | Use `"{{ $sys.id }}-pvc"` as the PVC and PV name |
| `gitConfiguration` and `artifactRelativePath` both set on same entry | Build error — ambiguous source | Use one or the other per provider entry, never both |
