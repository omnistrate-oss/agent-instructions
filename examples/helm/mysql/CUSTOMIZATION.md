# Customization Discovery — MySQL (Bitnami) Air-Gapped Installer

Chart: `bitnami/mysql` version **14.0.3** (appVersion 9.4.0)
Deployment model: **Air-gapped / onPremDeployment** (defense customer, zero connectivity)

---

## Three-Tier Parameter Table

Produced per `HELM_ONBOARDING_REFERENCE.md §Customization discovery` after the zero-param instance
reaches RUNNING. Present this table for ISV approval before implementing any Tier-1 parameter.

| Tier | Chart value path | Customer-visible name | Type | Default | Rationale |
|------|------------------|-----------------------|------|---------|-----------|
| **Tier 1** | `auth.rootPassword` | Root Password | Password | _(required)_ | Must be set by customer; never expose via export |
| **Tier 1** | `auth.database` | Database Name | String | `my_database` | Customer names their initial schema |
| **Tier 1** | `auth.username` | Database Username | String | `mysqluser` | Non-root access user |
| **Tier 1** | `auth.password` | Database User Password | Password | _(required)_ | Credential for the non-root user |
| **Tier 1** | `primary.persistence.size` | Primary Storage Size | String | `8Gi` | Customers need to size for their data volume |
| **Tier 1** | `privateRegistryUrl` (custom) | Private Registry URL | String | _(required)_ | Air-gapped: customer supplies their own registry URL for synced images |
| **Tier 1** | `releaseName` | Release Name | String | `mysql` | Helm release name; needed if multiple instances coexist in the cluster |
| **Tier 1** | `namespace` | Kubernetes Namespace | String | `mysql` | Namespace isolation for the installation |
| **Tier 2** | `architecture` | Deployment Architecture | String | `standalone` | `standalone` or `replication`; advanced ISV decision, not recommended for Tier 1 initially |
| **Tier 2** | `secondary.replicaCount` | Replica Count | Float64 | `1` | Only meaningful when architecture=replication; surfaced after architecture param is added |
| **Tier 2** | `secondary.persistence.size` | Replica Storage Size | String | `8Gi` | Only meaningful for replication architecture |
| **Tier 2** | `tls.enabled` | Enable TLS | Boolean | `false` | In-cluster TLS; useful advanced option but adds cert management complexity |
| **Tier 2** | `metrics.enabled` | Enable Metrics Exporter | Boolean | `false` | mysqld_exporter sidecar; useful for on-prem Prometheus but increases image count |
| **Tier 2** | `primary.resources.requests.cpu` | CPU Request | String | `500m` | Tuning knob; ISV should set a validated default for the target node profile |
| **Tier 2** | `primary.resources.requests.memory` | Memory Request | String | `512Mi` | Tuning knob |
| **Tier 3** | `primary.persistence.storageClass` | — | — | `""` (cluster default) | Platform-owned; Omnistrate or customer admin controls StorageClass — never expose |
| **Tier 3** | `global.imageRegistry` | — | — | `""` | Platform-owned (wired by `MySQLImageSync` service); do not expose separately |
| **Tier 3** | `primary.service.type` | — | — | `ClusterIP` | Platform-owned endpoint wiring; exposing breaks Omnistrate networking |
| **Tier 3** | `primary.affinity` / `podAffinityPreset` | — | — | chart defaults | Omnistrate auto-injects node affinity; customer override breaks scheduling |
| **Tier 3** | `image.registry` / `image.repository` | — | — | `docker.io/bitnami/mysql` | Registry redirect owned by `MySQLImageSync`; must not be a free-form param |
| **Tier 3** | `auth.existingSecret` | — | — | `""` | Platform secret management via `$secret.*`; do not allow customers to substitute their own K8s secret |

---

## External Dependency Analysis

### Bundled dependency audit

The Bitnami MySQL chart (`Chart.yaml`) declares one dependency:

| Dependency chart | `dependencies:` key | Default enabled | Notes |
|------------------|---------------------|-----------------|-------|
| `bitnami/common` | `common` | Always included (library chart) | Provides helper templates; no workload, no data |

**No bundled database or cache subchart.** MySQL _is_ the dataplane — it has no `postgresql.enabled` or
`redis.enabled` toggle. Therefore:

- **Option B (managed cloud service) does not apply** to this onboarding. In an air-gapped site there are
  no cloud-managed services (RDS, ElastiCache, S3) — they require internet connectivity and cloud API
  access that the deployment model explicitly prohibits. Suggesting a replacement with RDS would be
  architecturally invalid. The chart's in-cluster stateful deployment (primary PVC) is the **only viable
  option** and chart defaults are mandatory.

  > If the guide's external-dependency section is read to imply Option B should always be presented, that
  > is a gap: the guide does not explicitly state "do not suggest Option B for air-gapped sites." This is
  > **recorded as a gap** in `mysql-gaps.md`.

### Image registry dependency (air-gapped specific)

The chart pulls three images (from `Chart.yaml` annotations):

| Image | Tag |
|-------|-----|
| `docker.io/bitnami/mysql` | `9.4.0-debian-12-r1` |
| `docker.io/bitnami/mysqld-exporter` | `0.17.2-debian-12-r16` |
| `docker.io/bitnami/os-shell` | `12-debian-12-r50` |

All three must be embedded into the installer artifact (`pullMode: INSTALLER_EMBED`) and pushed to the
customer's `privateRegistryUrl` at install time. The `global.imageRegistry` chart value is overridden
to redirect all pulls to the customer's internal registry.

Note: the installer supports **one image registry** per Plan (per
`DEPLOYMENT_MODELS_REFERENCE.md §Air-gapped concept`). All three images share the same
`docker.io/bitnami` source and are captured by the `MySQLImageSync` service.

### Licensing

An air-gapped deployment cannot auto-renew its license. The signed offline license expires after
`licenseExpirationInDays` (set to 365 in spec). The customer must:

1. Mount the generated secret `service-plan-subscription-license` at `/var/subscription/` in the chart's
   primary pod (via `extraVolumes`/`extraVolumeMounts` chart values — **not yet wired in this spec**;
   recorded as a gap).
2. Integrate the Omnistrate licensing SDK (Go or Java) to call `ValidateLicense` at startup.
3. Plan for license renewal before expiration (offline artifact transfer).
