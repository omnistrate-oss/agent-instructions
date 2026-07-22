# Customization Discovery — RabbitMQ (Bitnami Helm chart 16.0.14)

_Generated during Omnistrate onboarding simulation (Phase 5 of the universal workflow).
Source: `helm show values bitnami/rabbitmq --version 16.0.14` and `helm show readme bitnami/rabbitmq`._

---

## Three-tier parameter table

| Tier | Helm values key | Display name | Type | Default | Rationale |
|------|----------------|--------------|------|---------|-----------|
| **Tier 1** | `auth.username` | Admin Username | String | `"admin"` | Customers need to know (or set) the username for AMQP and management UI login. |
| **Tier 1** | `auth.password` | Admin Password | Password | _(required)_ | Required credential; must not be exported. |
| **Tier 1** | `replicaCount` | Replica Count | Float64 | `"3"` | Cluster size directly controls HA and throughput; customer-relevant. Must be odd for quorum queues. |
| **Tier 1** | `persistence.size` | Storage Size (GiB) | Float64 | `"10"` | Message durability depends on disk; undersizing causes data loss under load. |
| **Tier 1** | `memoryHighWatermark.value` | Memory High Watermark | Float64 | `"0.4"` | Controls when RabbitMQ throttles publishers; tuning this is a common operational need for high-throughput customers. |
| **Tier 2** | `clustering.partitionHandling` | Partition Handling | String | `"autoheal"` | `pause_minority` is safer for quorum queues but breaks 2-of-3 splits; advanced use only. |
| **Tier 2** | `extraPlugins` | Extra Plugins | String | `"rabbitmq_auth_backend_ldap"` | LDAP auth and Prometheus exporter are optional; expose only if customers request LDAP/SSO integration. |
| **Tier 2** | `resources.requests.memory` | Memory Request | String | `"512Mi"` | Sizing knob; relevant for large workloads, but instance-type selection is the better lever. |
| **Tier 3** | `global.storageClass` / `persistence.storageClass` | Storage Class | — | `""` (platform default) | Omnistrate selects the appropriate StorageClass (gp3 on AWS); exposing this lets customers break storage provisioning. |
| **Tier 3** | `service.type` / `service.annotations` | Service type | — | `LoadBalancer` w/ external-dns annotation | Omnistrate owns endpoint wiring; exposing service type breaks DNS and LB provisioning. |
| **Tier 3** | `clustering.addressType` | Cluster address type | — | `"hostname"` | Internal clustering topology; must not be changed by customers. |
| **Tier 3** | `image.registry` / `image.repository` / `image.tag` | Image location | — | `docker.io/bitnami/rabbitmq:4.1.3-debian-12-r1` | Image registry/repository overrides break the managed substrate and image-pull path. |
| **Tier 3** | `affinity` / `nodeAffinityPreset` | Node affinity | — | _(chart default, overridden by Omnistrate injection)_ | Omnistrate auto-injects node affinity and pod anti-affinity; customer override breaks scheduling. |

---

## External dependency analysis

RabbitMQ **is the service itself** — it is not a subchart dependency bundled into a parent application. The Bitnami RabbitMQ chart:

- Has one dependency in `Chart.yaml`: `bitnami/common` (library chart, no workload — Tier 3 internal).
- Ships no `postgresql`, `redis`, or `minio` subchart.
- Has no `externalDatabase` or `externalCache` value block.
- Persists data to local PVCs (Kubernetes StatefulSet + EBS gp3 on AWS).

**Conclusion: no managed-service replacement applies.** RabbitMQ stores messages and cluster metadata on its own persistent volumes; there is no bundled external database, cache, or object-storage dependency to replace with a terraform-managed cloud service (RDS/ElastiCache/S3). The external-dependency analysis from `HELM_ONBOARDING_REFERENCE.md §"External dependencies"` is not applicable to this onboarding.

If a future customer tier requires durable off-cluster message archiving (e.g. shovel to S3), that would be a new service component added alongside RabbitMQ — not a chart-dependency replacement.
