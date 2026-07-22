# Customization Reference — Redis (Bitnami Helm Chart v27.0.15)

Chart: `bitnami/redis` version `27.0.15` (appVersion `8.8.0`)
Artifact Hub: https://artifacthub.io/packages/helm/bitnami/redis

---

## Three-Tier Classification Table

### Tier 1 — Recommended Customer-Facing (`apiParameters`)

These values become `apiParameters` wired into `chartValues` via `$var.<key>` or `$secret.*`.

| Chart Value Path | apiParameter key | Type | Default | modifiable | Notes |
|---|---|---|---|---|---|
| `auth.password` | — (use `$secret.REDIS_PASSWORD`) | Password | — | false | Never export; Omnistrate-managed secret. |
| `architecture` | `architecture` | String (options) | `"replication"` | false | `standalone` or `replication`. Cannot change post-create without re-provisioning. |
| `replica.replicaCount` | `numReplicas` | Float64 | `"1"` | true | How many replica nodes; 0 = standalone-equivalent. |
| `master.persistence.size` / `replica.persistence.size` | `storageSizeGi` | String | `"8Gi"` | false | PVC size — cannot be shrunk; growing requires PVC resize. |
| compute (instance type) | `instanceType` | String | `"t4g.small"` | true | Controls node pool sizing via `compute.instanceTypes[].apiParam`. |

### Tier 2 — Optional / Advanced (hardcode in `chartValues`; offer as upgrade path)

| Chart Value Path | Proposed Default | Reason to keep hardcoded | Expose condition |
|---|---|---|---|
| `metrics.enabled` | `false` | Prometheus exporter sidecar; good default off for cost control | Offer if customer has a Prometheus stack |
| `sentinel.enabled` | `false` | High-availability sentinel topology; more complex and requires different client config | Offer for HA tiers |
| `master.resources` / `replica.resources` | `requests: {cpu: 100m, memory: 128Mi}` | Should scale with instance type; manual knob is advanced | Offer if customer needs fine-grained resource caps |
| `commonConfiguration` | chart default (`appendonly yes`, RediSearch/ReJSON modules) | Module loading is ISV policy | Offer if customer needs custom redis.conf additions |
| `replica.disableCommands` / `master.disableCommands` | `[FLUSHDB, FLUSHALL]` | Security default; customers rarely need to re-enable | Offer for advanced customers who need flush |
| `master.persistence.enabled` / `replica.persistence.enabled` | `true` | Data durability — hardcode true for production | Only expose for dev/test tiers where cost matters |
| `useHostnames` | `true` | Internal routing | Keep hardcoded |
| `clusterDomain` | `cluster.local` | Kubernetes cluster domain | Keep hardcoded |

### Tier 3 — Never Expose (Platform- or ISV-Owned)

| Chart Value Path | Reason |
|---|---|
| `global.imageRegistry` / `image.registry` / `image.repository` | Image registry override breaks Omnistrate's managed image-pull path. |
| `global.defaultStorageClass` / `master.persistence.storageClass` / `replica.persistence.storageClass` | StorageClass is Omnistrate-provisioned; customer override breaks PVC provisioning. |
| `master.service.type` / `replica.service.type` | Service type is how Omnistrate wires load balancers and DNS. Customer override breaks endpoint provisioning. |
| `master.service.annotations` / `replica.service.annotations` | External-DNS annotations controlled by `$sys.network.externalClusterEndpoint` — customer override breaks hostname assignment. |
| `master.affinity` / `replica.affinity` / `master.podLabels` | Node affinity is Omnistrate-managed via automatic injection (`chartAffinityControl.enableInjection: true`). Customer exposure breaks scheduling onto managed nodes. |
| `master.nodeSelector` / `replica.nodeSelector` / `master.tolerations` | Same reason as affinity — Omnistrate owns pod placement. |
| `namespaceOverride` / `fullnameOverride` | Omnistrate manages namespace and release naming for per-instance isolation. |
| `global.redis.password` | Password is managed via `$secret.REDIS_PASSWORD`; exposing the global override creates a conflict. |
| `auth.existingSecret` / `auth.existingSecretPasswordKey` | Omnistrate manages secrets injection; customer-supplied secrets are unsupported in this model. |
| `global.compatibility.openshift.*` | Platform-specific; Omnistrate cells run on standard Kubernetes. |
| `image.pullSecrets` | Private registry auth is managed at account level, not per-chart value. |
| `diagnosticMode.enabled` | ISV/support use only; exposes internal debug shell. |

---

## External Dependency Analysis

**Redis IS the data service.** The Bitnami Redis chart has no external database or object-storage dependency — it **is** the stateful data store. There is no bundled PostgreSQL, MySQL, or external-cache subchart.

**`Chart.yaml` dependencies:** only `bitnami/common` (version 2.41.0) — a utility library chart with no runtime workload. It is not a data dependency.

**Suggestion (not forced):** Redis is self-contained; no managed-cloud-service replacement applies. Persistence is on cluster PVCs backed by the Omnistrate-provisioned CSI driver. For disaster-recovery backups, a future lifecycle phase could add Omnistrate backup capability (snapshotting PVCs or using `BGSAVE`/AOF-copy to S3 via a backup workflow — not covered in this initial spec).

**Architecture note:** the `commonConfiguration` block in the chart's default values loads `redisearch.so` and `rejson.so` modules. These are bundled in Bitnami's Redis image and do not require external services, but they do increase memory footprint — factor into instance type selection.
