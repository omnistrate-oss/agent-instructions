# Customization Guide — HashiCorp Vault (chart 0.34.0)

Produced by simulated ISV onboarding. Tier classification follows
`HELM_ONBOARDING_REFERENCE.md` §Customization discovery.

---

## Three-Tier Parameter Table

| # | Chart value | Tier | Rationale | Omnistrate mapping |
|---|-------------|------|-----------|-------------------|
| 1 | `server.ha.replicas` | **Tier 1** | Core HA sizing; customer chooses quorum size (3 or 5) | `apiParameter` key `haReplicas` → `$var.haReplicas`, `Float64`, limits 3–5, `modifiable: false` |
| 2 | `server.dataStorage.size` | **Tier 1** | Per-node PVC size directly affects capacity | `apiParameter` key `storageSizeGi` → `$var.storageSizeGi`, `String`, `modifiable: false` |
| 3 | `server.resources.limits.cpu` | **Tier 1** | CPU throttling affects Vault latency in regulated workloads | `apiParameter` key `cpuLimit` → `$var.cpuLimit`, `String`, `modifiable: true` |
| 4 | `server.resources.limits.memory` | **Tier 1** | Vault unseal and token/policy caches are memory-sensitive | `apiParameter` key `memoryLimit` → `$var.memoryLimit`, `String`, `modifiable: true` |
| 5 | `compute.instanceTypes` | **Tier 1** | Instance type governs IOPS (raft-critical) and NVMe burst | `apiParameter` key `instanceType` → `cloudProvider: aws`, `modifiable: false` |
| 6 | `server.auditStorage.enabled` | **Tier 2** | Compliance teams may require audit device; adds second PVC | Hardcoded `false`; offer as advanced toggle if ISV confirms compliance tier |
| 7 | `server.auditStorage.size` | **Tier 2** | Only relevant when audit storage enabled | Hardcode `10Gi` conditional on audit enablement |
| 8 | `global.serverTelemetry.prometheusOperator` | **Tier 2** | Metrics integration; useful but not universal | Hardcode `false`; ISV can wire Omnistrate Grafana amenity instead |
| 9 | `injector.enabled` | **Tier 2** | Agent sidecar injection for app-level secret fetching | Hardcoded `false`; expose if ISV offers agent-injection as add-on |
| 10 | `server.resources.requests.*` | **Tier 2** | Fine tuning; defaults are reasonable | Hardcoded `250m` / `256Mi`; Tier-2 candidate if ISV offers multiple tiers |
| 11 | `global.tlsDisable` | **Tier 3** | TLS is handled at Omnistrate's LB layer; exposing this breaks the endpoint model | Hardcoded `true`; never expose |
| 12 | `server.dataStorage.storageClass` | **Tier 3** | Platform-provisioned; customer changing it breaks the managed substrate | Hardcoded `null` (use cluster default) |
| 13 | `server.service.type` | **Tier 3** | Omnistrate manages the endpoint; setting to LoadBalancer bypasses PrivateLink model | Hardcoded `ClusterIP` |
| 14 | `ui.serviceType` | **Tier 3** | Same as above — UI exposed through the same PrivateLink endpoint | Hardcoded `ClusterIP` |
| 15 | `server.ha.raft.config` (internals) | **Tier 3** | Raft topology, retry_join addresses, storage path — ISV-owned clustering contract | Hardcoded in `chartValues` |
| 16 | `injector.image.*`, `agentImage.*` | **Tier 3** | Image overrides break the managed image-pull path | ISV-owned; never expose |
| 17 | `global.imagePullSecrets` | **Tier 3** | No private registry in this scenario; platform pulls from public hashicorp registry | Hardcoded empty |

---

## External Dependency Analysis

### Storage backend — chart default: integrated raft over in-cluster PVCs

The Vault Helm chart's default in HA mode is `storage "raft"` backed by a
`PersistentVolumeClaim` on each raft peer (StatefulSet). This is a **self-contained,
in-cluster** dependency — no external cloud service.

**Assessment per HELM_ONBOARDING_REFERENCE.md §External dependencies:**

| Factor | Evaluation |
|--------|-----------|
| Durability / SLA | PVCs backed by EBS (aws) — durability is cloud-provider SLA, same as RDS EBS volumes. Adequate for most regulated workloads. |
| Backup story | Vault does not backup via Helm; manual raft snapshots or Vault's `/sys/storage/raft/snapshot` API must be scripted. An Omnistrate `backup` lifecycle verb could call this API, but no reference pattern exists in the current skill files — see GAP below. |
| Cost | No additional managed service cost. EBS PVCs are provisioned by Omnistrate's CSI. |
| Egress | No cross-AZ egress for storage (EBS is zone-pinned); relevant for multi-AZ raft. |
| BYOC implication | PVCs are provisioned in the customer's account — storage cost lands there. ✓ |

**Recommendation: keep the bundled raft/PVC backend (Option A).** There is no
practical managed-service substitute for Vault's storage layer: RDS or ElastiCache
are not valid Vault storage backends. S3 was a supported Vault storage backend in
older versions but is not supported in Vault 1.x/2.x OSS. The chart has no
`externalDatabase` equivalent for storage — raft is the canonical HA backend.

### Auto-unseal via AWS KMS — real-world requirement, NOT in chart defaults

Vault starts sealed after every restart. In production BYOC/PrivateLink deployments,
manual unseal is operationally unacceptable. The standard solution is **AWS KMS
auto-unseal** (`seal "awskms"` stanza in the Vault config). This is a common
production requirement.

**Guide coverage check:**
- `HELM_ONBOARDING_REFERENCE.md` §External dependencies covers RDS/ElastiCache/S3
  terraform modules but has **no KMS/IAM Terraform pattern for Vault auto-unseal**.
- `TERRAFORM_KUSTOMIZE_REFERENCE.md` (referenced by the guide) would be the right
  home for a KMS key + IAM role terraform module, but this pattern is absent.

**Gap recorded:** see `vault-gaps.md` GAP-2.

**Terraform for KMS auto-unseal (TODO-GAP — sourced from HashiCorp docs pattern,
syntax unverified against Omnistrate terraform module schema):**

```hcl
# TODO-GAP: verify against TERRAFORM_KUSTOMIZE_REFERENCE.md §Managed-service modules
# before including in a production spec.yaml terraformConfigurations block.
resource "aws_kms_key" "vault_autounseal" {
  description             = "Vault auto-unseal key — ${var.instance_id}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags = {
    "omnistrate.com/managed-by" = "omnistrate"
  }
}

resource "aws_kms_alias" "vault_autounseal" {
  name          = "alias/vault-autounseal-${var.instance_id}"
  target_key_id = aws_kms_key.vault_autounseal.key_id
}

# IAM policy for Vault pods to use the KMS key (attach to the node role or a IRSA role)
resource "aws_iam_policy" "vault_kms" {
  name = "vault-autounseal-${var.instance_id}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
      Resource = aws_kms_key.vault_autounseal.arn
    }]
  })
}

output "kms_key_id" {
  value = aws_kms_key.vault_autounseal.key_id
}
```

To wire KMS auto-unseal, the Vault server HCL config (`server.ha.raft.config`)
must include:

```hcl
seal "awskms" {
  region     = "<AWS_REGION>"
  kms_key_id = "<KMS_KEY_ID_FROM_TERRAFORM_OUTPUT>"
}
```

This would require a `dependsOn` terraform service in the spec and
`{{ $kmsInfra.out.kms_key_id }}` injected into the raft config — a pattern not
demonstrated in the current skill files.

### Subchart dependencies (Chart.yaml `dependencies:`)

The hashicorp/vault 0.34.0 chart has **no bundled subcharts** in its dependencies
list. All components (server, injector, csi-provider) are in-chart templates
controlled by `enabled` flags. No PostgreSQL/Redis/Minio subchart to disable.
