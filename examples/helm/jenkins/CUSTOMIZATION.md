# Jenkins — Customization & External Dependency Analysis

Chart: `jenkins/jenkins` version `5.9.42`
Deployment model: BYOC-K8s (`byoaDeployment`, deployed with `--cloud-provider byoc-onprem --region on-prem`)

---

## Three-Tier Parameter Table

Parameters surfaced from `helm show values jenkins/jenkins` (version 5.9.42).
Tier definitions per `HELM_ONBOARDING_REFERENCE.md` §"Customization discovery".

| Value path | Tier | Rationale | `spec.yaml` mapping |
|---|---|---|---|
| `controller.admin.username` | **Tier 1** | Every customer sets their admin credentials | `apiParameter: adminUser` (String, `modifiable: false`, `export: true`) |
| `controller.admin.password` | **Tier 1** | Credential — must be customer-set | `apiParameter: adminPassword` (Password, `modifiable: false`, `export: false`) |
| `persistence.size` | **Tier 1** | Jenkins home disk size is a core capacity decision | `apiParameter: persistenceSizeGi` (String, `modifiable: false`) |
| `controller.installPlugins` | **Tier 2 — hardcoded default** | Plugin list is ISV-defined; customers can request additions but should not free-form this on create. The default set (kubernetes, workflow-aggregator, git, configuration-as-code) is the minimal opinionated baseline. Expose as Tier 1 only if the ISV wants a per-customer plugin list. | Hardcoded in `chartValues` |
| `controller.JCasC` (JCasC YAML block) | **Tier 2 — hardcoded / GAP** | A raw JCasC YAML block is a structured nested object. `HELM_ONBOARDING_REFERENCE.md` documents `type: Json` for structured parameters but provides no explicit guidance for a multi-line YAML string intended to be injected verbatim into `chartValues`. Exposing a raw YAML block as `type: String` risks injection errors; `type: Json` may not map cleanly to YAML syntax. **This is a guidance gap (see gap report).** Default: hardcode an empty JCasC block; ISVs requiring customer-supplied JCasC should document this as a post-deploy customization via the Jenkins UI or a secret-mounted ConfigMap. | Hardcoded / not exposed |
| `controller.resources` (cpu/memory limits) | **Tier 2 — hardcoded default** | Sensible defaults (50m–2000m CPU, 256Mi–4096Mi memory) are set by the chart and kept as ISV defaults | Hardcoded in `chartValues` |
| `controller.numExecutors` | **Tier 2** | Advanced tuning; chart default is 0 (determined by executorMode) | Hardcoded at chart default |
| `agent.enabled` | **Tier 2 — hardcoded true** | Kubernetes dynamic agents are a primary Jenkins-on-K8s value proposition; enabled by default | Hardcoded `true` in `chartValues` |
| `controller.serviceType` | **Tier 3 — never expose** | Service type controls K8s networking; Omnistrate owns endpoint wiring | Hardcoded `ClusterIP` |
| `controller.agentListenerServiceType` | **Tier 3** | Agent listener wiring is platform-internal | Hardcoded `ClusterIP` |
| `persistence.storageClass` | **Tier 3 — never expose** | StorageClass is cluster-infrastructure-owned; exposing it breaks the managed substrate | Omitted (cluster default StorageClass applies) |
| `persistence.accessMode` | **Tier 3** | PVC access mode is platform-managed | Hardcoded `ReadWriteOnce` |
| `controller.image.*` | **Tier 3** | Image registry/repository overrides break image-pull path | Omitted (chart default) |
| `nameOverride` / `fullnameOverride` | **Tier 3** | Helm release naming is Omnistrate-managed | Omitted |
| `clusterZone` | **Tier 3** | Internal cluster DNS — platform-owned | Omitted (chart default `cluster.local`) |

---

## External Dependency Analysis

### PVC / Persistence

Jenkins requires a PVC for `$JENKINS_HOME`. The chart handles PVC provisioning natively via `persistence.enabled: true`.

**Analysis:** The chart is **self-contained with PVC** — no external managed service (e.g., RDS, ElastiCache, S3) is bundled or required. Jenkins stores configuration and job history locally on its PVC.

**BYOC-K8s implication:** On BYOC-K8s, Omnistrate does NOT provision the StorageClass — the customer's cluster must have a default StorageClass (or a named one). This is a **customer prerequisite**, not something the ISV controls via the spec. The guide (`DEPLOYMENT_MODELS_REFERENCE.md` §BYOC-K8s) confirms: storage must be a pre-existing cluster capability. No managed-service suggestion applies here.

**Managed-service suggestion (BYOC-K8s): N/A.** Chart default (PVC) is the correct choice. Jenkins' persistence is not a subchart dependency that maps cleanly to RDS/ElastiCache/S3.

### Kubernetes Agent Pool (dynamic agents)

The chart bundles a Kubernetes plugin for dynamic pod-based agent provisioning. This runs within the same cluster — no external dependency. Enabled by default (`agent.enabled: true`).

### JCasC (Configuration-as-Code)

JCasC is an in-process plugin (`configuration-as-code`) that reads YAML config from the pod. No external data store required. Customer-supplied JCasC overrides are a Tier-2 advanced concern; see gap analysis.

---

## Summary

The Jenkins Helm chart is self-contained. Only three Tier-1 parameters are exposed at launch: admin username, admin password, and persistence size. The ISV owns the plugin baseline, resource limits, and all networking wiring. For BYOC-K8s, the customer's cluster must supply a working StorageClass — this is a deployment prerequisite to communicate in onboarding documentation.
