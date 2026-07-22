# Harbor — Customization Reference (BYOC-K8s)

Chart: `harbor/harbor` v1.19.1 (Harbor app v2.15.1)
Deployment model: BYOC-K8s (`byoaDeployment`, deployed `--cloud-provider byoc-onprem --region on-prem`)

---

## Three-Tier Parameter Table

Derived from `helm show values harbor/harbor`. Source fields are the real chart value keys.

| Tier | Parameter / Chart Value | Default | Rationale |
|------|------------------------|---------|-----------|
| **Tier 1 — Customer-facing** | `externalURL` | (required) | Customer must set the hostname their ingress uses; Harbor embeds this URL in docker push/pull instructions and token URLs. |
| **Tier 1 — Customer-facing** | `harborAdminPassword` (→ `adminPassword` API param) | (required) | Initial admin credential; Password type, not exportable. |
| **Tier 1 — Customer-facing** | `persistence.persistentVolumeClaim.registry.size` (→ `registryStorageGi`) | `50Gi` | Registry image storage PVC size. Customer controls capacity; safe to surface. |
| **Tier 1 — Customer-facing** | `logLevel` | `info` | Log verbosity. Safe to expose; affects observability. |
| **Tier 2 — Optional / advanced** | `internalTLS.enabled` | `false` | Enable mTLS between Harbor internal components. Adds complexity; default off. |
| **Tier 2 — Optional / advanced** | `metrics.enabled` | `false` | Expose Prometheus metrics. Useful but not required for basic operation. |
| **Tier 2 — Optional / advanced** | `trivy.enabled` / `trivy.gitHubToken` | `true` | Vulnerability scanner toggle + GitHub token for DB updates. ISV may hardcode. |
| **Tier 2 — Optional / advanced** | `cache.enabled` / `cache.expireHours` | `false` / `24` | Redis caching layer for high-concurrency pull. Advanced tuning knob. |
| **Tier 2 — Optional / advanced** | `persistence.imageChartStorage.type` | `filesystem` | Switch to `s3`/`gcs`/`azure` for cloud-native storage. See External Dependencies below. |
| **Tier 2 — Optional / advanced** | `updateStrategy.type` | `RollingUpdate` | Set `Recreate` if RWX volumes are unavailable. |
| **Tier 3 — Never expose (platform/ISV-owned)** | `persistence.persistentVolumeClaim.*.storageClass` | `""` (cluster default) | StorageClass is Tier 3 — exposing it lets customers break managed storage. Customer cluster must have a default StorageClass. |
| **Tier 3 — Never expose (platform/ISV-owned)** | `expose.type` | `clusterIP` | Service type controls how Omnistrate wires endpoints. ISV-set per deployment model. |
| **Tier 3 — Never expose (platform/ISV-owned)** | `expose.ingress.*` / `expose.loadBalancer.*` | N/A | Omnistrate or customer's own ingress controller manages this on BYOC-K8s. |
| **Tier 3 — Never expose (platform/ISV-owned)** | `*.image.repository` / `*.image.tag` | chart defaults | Image registry/repository overrides break the managed image-pull path. |
| **Tier 3 — Never expose (platform/ISV-owned)** | `secretKey` | ISV-hardcoded 16-char string | Encryption key for Harbor data; must remain stable. ISV-owned; never exposed. |
| **Tier 3 — Never expose (platform/ISV-owned)** | `*.affinity` / `*.nodeSelector` | N/A | Placement is Omnistrate-managed (automatic affinity injection enabled). |

---

## External Dependency Analysis

### What Harbor bundles

Harbor's chart bundles three in-cluster dependencies controlled by `type: internal` / `type: external` toggles:

| Dependency | Chart value | Default | External alternative |
|------------|-------------|---------|----------------------|
| PostgreSQL (metadata DB) | `database.type: internal` | in-cluster StatefulSet + PVC | `database.type: external` + `database.external.host/port/username/password` |
| Redis (job queue + cache) | `redis.type: internal` | in-cluster StatefulSet + PVC | `redis.type: external` + `redis.external.addr` |
| Image/chart storage | `persistence.imageChartStorage.type: filesystem` | in-cluster PVC on registry pod | Switch to `s3`, `gcs`, `azure`, `swift`, `oss` |

### BYOC-K8s verdict: Option A (in-cluster defaults)

**Option A is the correct choice for BYOC-K8s.** Here is the reasoning derived from the guide:

> From `HELM_ONBOARDING_REFERENCE.md` §External dependencies:
> "BYOC implication — terraform runs in **whichever account the deployment model targets**
> (your account for hosted; the customer's account for BYOC), so the managed service and
> its cost land there too."

`byoc-onprem` (BYOC-K8s) has **no cloud account target** — Omnistrate provisions no infra and
has no AWS/GCP/Azure account to execute terraform in. Therefore the Option B pattern
(terraform-managed RDS / ElastiCache / S3) from the guide does not cleanly apply here.
The guide does not explicitly address this gap (see GAP REPORT).

In-cluster PostgreSQL + Redis + PVC filesystem storage (Option A) is the appropriate default:
- No external account needed.
- Data is durable on customer-owned cluster PVCs (customer controls backup/durability SLAs).
- Consistent with BYOC-K8s ownership model: customer owns storage, ingress, and cluster infra.

### S3 storage backend note (Tier-2 option for egress-capable customers)

Customers whose clusters have egress to an S3-compatible endpoint (AWS S3, MinIO, etc.) can
switch the image/chart storage backend to avoid scaling PVC storage:

```yaml
persistence:
  imageChartStorage:
    disableredirect: true   # required for S3-compatible (e.g. MinIO) backends
    type: s3
    s3:
      region: us-east-1
      bucket: <customer-bucket>
      # accesskey/secretkey OR existing secret
```

This is a **Tier-2** configuration: the ISV should provide it as documentation or a custom
config block, not as a customer-facing API parameter (it requires customers to provision their
own bucket, credentials, and network path — out of Omnistrate's scope on BYOC-K8s).

### Cluster prerequisites (customer responsibility on BYOC-K8s)

Per `DEPLOYMENT_MODELS_REFERENCE.md` §BYOC-K8s target-cluster prerequisites:

| Requirement | Harbor implication |
|-------------|-------------------|
| Default StorageClass | Required for all PVCs (registry, DB, Redis, jobservice, trivy). Cluster must have a default StorageClass or explicit classes set. |
| Ingress controller | Customer must provide an ingress controller (nginx, HAProxy, etc.) and configure it to route to the `harbor` ClusterIP service on port 80/443. |
| DNS routing | `externalURL` must resolve to the customer's ingress endpoint. ISV/customer coordinates this. |
| Outbound egress | Cluster must reach Harbor's helm repo (`helm.goharbor.io`) and docker.io for image pulls on first install. |
| Pod networking | Standard CNI required; Harbor components communicate internally over ClusterIP. |
