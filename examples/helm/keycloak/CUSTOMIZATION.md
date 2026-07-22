# Keycloak — Customization Guide

Chart: `bitnami/keycloak` v25.2.0 (Keycloak 26.3.3)
Deployment model: Hosted (AWS us-east-1)

---

## Parameter Tier Table

| Tier | Value path (helm) | `apiParameter` key | Type | Default | Rationale |
|------|-------------------|--------------------|------|---------|-----------|
| **1 — Customer-facing** | `auth.adminUser` | `adminUser` | String | `"admin"` | First Keycloak admin login |
| **1 — Customer-facing** | `auth.adminPassword` | `adminPassword` | Password | *(required)* | Credential — never exported |
| **1 — Customer-facing** | `replicaCount` | `replicaCount` | Float64 | `"1"` | Scale pods; modifiable at runtime |
| **1 — Customer-facing** | *(compute)* | `instanceType` | String | `"t3.medium"` | EC2 size via dropdown |
| **1 — Customer-facing** | `externalDatabase.password` | `dbPassword` | Password | *(required)* | RDS DB password; also fed to terraform |
| **2 — Optional/advanced** | `keycloakConfigCli.*` | — | — | chart default | Realm import tooling; hardcoded |
| **2 — Optional/advanced** | `extraEnvVars` | — | — | `[]` | Custom JVM/KC env; hardcoded |
| **2 — Optional/advanced** | `cache.stack` | — | — | `kubernetes` | Infinispan clustering mode; hardcoded |
| **3 — Never expose** | `service.type` / annotations | — | — | ISV-managed | Omnistrate wires the LB/DNS |
| **3 — Never expose** | `postgresql.enabled` | — | — | `false` (prod) | Subchart toggle — ISV decision |
| **3 — Never expose** | `externalDatabase.host` | — | — | terraform output | Injected from `{{ $keycloakDb.out.db_endpoint }}` |
| **3 — Never expose** | pod affinity / node selectors | — | — | Omnistrate auto-injected | Breaks managed scheduling if exposed |
| **3 — Never expose** | `image.registry` / `image.repository` | — | — | `docker.io/bitnami/keycloak` | Platform-managed image path |

---

## PostgreSQL Dependency — Option A vs Option B

The Bitnami Keycloak chart bundles a `postgresql` subchart that is **enabled by default**
(`postgresql.enabled: true`). It provides a fully working in-cluster database with no
extra cloud cost.

### Suggestion (presented to the ISV before production go-live)

#### Option A — Keep the bundled PostgreSQL subchart (default)

- `postgresql.enabled: true`; remove the `externalDatabase` block.
- Data lives on cluster PVCs managed by the chart.
- No extra cloud service cost; no additional IAM configuration.
- **Recommended for:** dev/test, lower tiers, quick evaluation.

**Decision factors that favour Option A:**

- Lower total cost (no RDS hourly rate or cross-AZ egress).
- Simpler spec (no terraform service, no `dependsOn`).
- Acceptable for data that is replayable or where the ISV manages backups at the Helm level.

#### Option B — Replace with terraform-managed Amazon RDS (SUGGESTED for production)

- `postgresql.enabled: false`; `externalDatabase.host` injected from RDS terraform output.
- RDS PostgreSQL (engine 15.x, `db.t3.medium`, 7-day automated backups).
- Carries provider-grade durability (99.95% SLA), multi-AZ option, and native RDS snapshots.
- **Recommended for:** production tiers, data-sovereignty-sensitive customers, SLA-bound deployments.

**Decision factors that favour Option B (why the ISV chose this for prod):**

| Factor | Option A (in-cluster) | Option B (RDS) |
|--------|----------------------|----------------|
| Durability | PVC on cluster disk; no cross-AZ replication | RDS multi-AZ; provider SLA |
| Backup story | Chart-managed PVC snapshots; manual effort | Native RDS automated snapshots (7-day retention configured) |
| Cost | No extra charge | ~$0.026/hr db.t3.medium + storage; possible cross-AZ egress |
| BYOC implication | PVC lives in customer cluster (BYOC) | RDS provisioned in customer's account (terraform runs there) |
| Operational risk | PVC lifecycle tied to Helm release | Managed independently; survives Helm uninstall |

**The ISV accepted Option B for the production Plan.** The dev tier may use Option A
by toggling `postgresql.enabled: true` and removing the `externalDatabase` chartValues block.

---

## Wiring Summary (Option B — how the value paths connect)

```
spec.yaml
  keycloakDb (terraform service)
    variablesValuesFileOverride:
      db_password = "{{ $var.dbPassword }}"        # $var sourced from apiParameter key=dbPassword

  keycloak (helm service)
    dependsOn: [keycloakDb]
    chartValues:
      postgresql:
        enabled: false                             # disables bitnami/postgresql subchart
      externalDatabase:
        host: "{{ $keycloakDb.out.db_endpoint }}"  # terraform output consumed with {{ }}
        port: 5432
        user: keycloak_user
        database: keycloak
        password: $var.dbPassword                  # bare $var (same service) — no {{ }}
```
