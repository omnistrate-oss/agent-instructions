# Helm Onboarding Examples

These ten examples were produced by **end-to-end onboarding simulations** run against
real [Artifact Hub](https://artifacthub.io/) Helm charts. In each simulation, an agent
was given only the `omnistrate-fde` skill files and asked to onboard a specific chart
under a specific deployment model — producing a `spec.yaml`, a `CUSTOMIZATION.md`
(three-tier parameter analysis + external-dependency decisions), a `DEPLOYMENT_OVERVIEW.md`,
and a `deployment-overview.svg`, plus terraform where a managed-service dependency was
introduced. The goal was to stress-test the skills against real charts and surface gaps.

The set deliberately exercises **all four deployment models** (hosted, BYOC, BYOC-K8s,
air-gapped) and a range of chart shapes (single-service, umbrella, stateful TCP cluster,
HTTP app, database with external dependencies).

## The ten examples

| Example | Chart | Version | Deployment model |
|---------|-------|---------|------------------|
| `redis/` | `bitnami/redis` | 27.0.15 | Hosted (`hostedDeployment`) |
| `postgresql/` | `bitnami/postgresql` | 18.8.0 | BYOC (`byoaDeployment`) |
| `vault/` | `hashicorp/vault` | 0.34.0 | BYOC + PrivateLink (`byoaDeployment`) |
| `gitlab/` | `gitlab/gitlab` | 10.2.0 | Multi-model: Hosted + BYOC (`hostedDeployment` + `byoaDeployment`) |
| `harbor/` | `harbor/harbor` | 1.19.1 | BYOC-K8s (`byoaDeployment`, `--cloud-provider byoc-onprem`) |
| `keycloak/` | `bitnami/keycloak` | 25.2.0 | Hosted (`hostedDeployment`) |
| `jenkins/` | `jenkins/jenkins` | 5.9.42 | BYOC-K8s (`byoaDeployment`, `--cloud-provider byoc-onprem`) |
| `rabbitmq/` | `bitnami/rabbitmq` | 16.0.14 | Hosted (`hostedDeployment`) |
| `kafka/` | `bitnami/kafka` | 32.4.3 | BYOC (`byoaDeployment`) |
| `mysql/` | `bitnami/mysql` | 14.0.3 | Air-gapped (`onPremDeployment`) |

## `TODO-GAP` markers

Some examples contain `TODO-GAP` (and `TODO-SIMULATED`) markers. These are **not bugs in
the examples** — they mark the exact points where the onboarding agent could not derive a
step from the skill files alone and had to guess, defer, or stub. Each marker drove a
skill improvement. The gaps behind them are now **addressed in the reference files**:

- **Helm lifecycle** (backup / stop-start) — `HELM_ONBOARDING_REFERENCE.md`
  §Lifecycle: backups and stop/start; S3-as-backup-target variant in
  `TERRAFORM_KUSTOMIZE_REFERENCE.md`.
- **Parameter mechanics** (`$secret.*` vs `Password`, Kubernetes quantity strings,
  `type: json`, storage-size `modifiable: false`, Helm→terraform parameter threading,
  RDS `host:port` vs `address`) — `HELM_ONBOARDING_REFERENCE.md` §Templating,
  §Per-parameter mapping guidance, §External dependencies.
- **Networking** (`loadBalancers.tcp`, stateful per-broker addressing,
  `network.ports` / `networkingType` semantics, BYOC-K8s HTTP exposure, chart Service
  name discovery) — `HELM_ONBOARDING_REFERENCE.md` §Exposing endpoints;
  `DEPLOYMENT_MODELS_REFERENCE.md` §BYOC-K8s.
- **External deps × models** (model-applicability box, umbrella subchart-disable
  mechanisms, multi-bucket S3, pre-install secrets, licensing mount, air-gapped
  `internal: true`, BYOC-K8s account fields) — `HELM_ONBOARDING_REFERENCE.md`
  §External dependencies + §Licensing; `DEPLOYMENT_MODELS_REFERENCE.md`.
- **Distribution artifact** (PrivateLink SVG row, multi-model SVG naming) —
  `DISTRIBUTION_REFERENCE.md` §Recipe.

The full gap reports live in `.superpowers/sim/<chart>-gaps.md`.

> These directories are validation artifacts captured as-is from the simulations; they
> are illustrative, not maintained production specs. Re-verify chart versions and value
> keys against the current chart before reusing any snippet.
