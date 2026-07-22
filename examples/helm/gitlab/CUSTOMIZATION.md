# GitLab Helm Chart — Customization Guide

Chart: `gitlab/gitlab` version `10.2.0` (appVersion `v19.2.0`)
Source: `helm show values gitlab/gitlab | head -600` plus docs at https://docs.gitlab.com/charts/

> **Note on chart scale:** GitLab has one of the largest Helm charts in the ecosystem with
> hundreds of top-level and nested value paths. This table covers the ~30 most relevant values
> for a production SaaS onboarding. The full surface is documented at
> https://docs.gitlab.com/charts/charts/globals and per-subchart pages.

---

## External Dependency Decision

### Option A (chart defaults — in-cluster bundled deps)
- PostgreSQL: bundled via internal subchart (no toggle in umbrella values — chart uses in-cluster Postgres by default when `global.psql.host` is empty)
- Redis: in-cluster (when `global.redis.host` is empty, chart uses bundled redis subchart)
- Object storage: internal minio path (when `global.appConfig.object_store.enabled: false`)
- **Suitable for:** dev/test, starter tier, ephemeral demos
- **Limitations:** data lives on PVCs; no managed backup SLA; PVCs lost on cluster recreation

### Option B (chosen for production — terraform-managed cloud services)
- PostgreSQL → **Amazon RDS** (multi-AZ, automated backups, provider durability SLA)
- Redis → **Amazon ElastiCache** (managed failover, AOF persistence optional)
- Object storage → **Amazon S3** (11-nines durability, cross-region replication possible)
- **Wired via:** `global.psql.host`, `global.redis.host`, `global.appConfig.object_store.*`
- **Disable in-cluster:** set `global.psql.host` (non-empty value tells chart to skip internal postgres); same for redis

**Decision factors applied:**
| Factor | Analysis | Decision |
|--------|----------|----------|
| Durability / SLA | GitLab data (repos, issues, CI artifacts) needs ≥ 99.99% durability | Option B |
| Backup story | RDS automated snapshots + S3 versioning vs chart backup job | Option B |
| Cost | Adds ~$200–500/month managed service cost | Acceptable for production tier |
| Egress | Same AZ deployment cells minimize cross-AZ cost | Mitigated |
| BYOC implication | Terraform runs in customer account (enterprise BYOC tier); cost lands there | Documented |

---

## Three-Tier Parameter Table

| Tier | Value path | Default | Notes |
|------|-----------|---------|-------|
| **Tier 1** | `global.edition` | `ee` | `ee` or `ce`; wired as `gitlabEdition` apiParam |
| **Tier 1** | `global.initialRootPassword.secret` | (none) | Root password secret; wired as `rootPassword` apiParam |
| **Tier 1** | `gitlab.webservice.replicaCount` | `2` | Webservice replicas; wired as `webserviceReplicas` apiParam |
| **Tier 1** | `global.psql.host` | `""` (internal) | RDS endpoint from terraform output |
| **Tier 1** | `global.psql.database` | `gitlabhq_production` | Database name |
| **Tier 1** | `global.psql.username` | `gitlab` | Database user |
| **Tier 1** | `global.redis.host` | `""` (internal) | ElastiCache endpoint from terraform output |
| **Tier 1** | `global.appConfig.object_store.enabled` | `false` | Enable S3 object storage |
| **Tier 1** | `global.appConfig.lfs.bucket` | `git-lfs` | LFS bucket name |
| **Tier 1** | `global.appConfig.artifacts.bucket` | `gitlab-artifacts` | CI artifacts bucket |
| **Tier 1** | `global.appConfig.uploads.bucket` | `gitlab-uploads` | User uploads bucket |
| **Tier 1** | `global.appConfig.packages.bucket` | `gitlab-packages` | Package registry bucket |
| **Tier 1** | `global.appConfig.backups.bucket` | `gitlab-backups` | Backups bucket |
| **Tier 2** | `gitlab.sidekiq.replicaCount` | `1` | Background job workers; advanced tuning |
| **Tier 2** | `global.smtp.enabled` | `false` | Outgoing email; configure for notifications |
| **Tier 2** | `global.smtp.address` | `smtp.mailgun.org` | SMTP host |
| **Tier 2** | `global.smtp.port` | `2525` | SMTP port |
| **Tier 2** | `global.appConfig.omniauth.enabled` | `false` | SSO/OAuth providers |
| **Tier 2** | `prometheus.install` | `true` | Built-in Prometheus; disable if external monitoring |
| **Tier 2** | `gitlab-runner.install` | `true` | Built-in CI runner; disable if external |
| **Tier 2** | `global.appConfig.cron_jobs` | `{}` | Cron job schedules for cleanup workers |
| **Tier 2** | `global.praefect.enabled` | `false` | Gitaly Cluster (Praefect) for HA git storage |
| **Tier 2** | `global.appConfig.externalDiffs.enabled` | `false` | Store MR diffs in object storage |
| **Tier 2** | `global.appConfig.terraformState.enabled` | `false` | Terraform state storage |
| **Tier 2** | `global.appConfig.dependencyProxy.enabled` | `false` | Dependency proxy cache |
| **Tier 3** | `global.hosts.domain` | (required) | Managed by `$sys.network.externalClusterEndpoint` |
| **Tier 3** | `nginx-ingress.enabled` | `false` | Cell amenity provides ingress — do not expose |
| **Tier 3** | `installCertmanager` | `true` | Cell amenity provides cert-manager — set false |
| **Tier 3** | `global.image.pullPolicy` | `IfNotPresent` | Image pull policy — ISV-owned |
| **Tier 3** | `global.gatewayApi.enabled` | `true` | Omnistrate controls gateway/ingress setup |

**Coverage cutoff:** This table covers the 30 most impactful values. The chart has 300+ additional
values for Gitaly, KAS, Pages, Zoekt (search), OpenBao, AI Gateway, Geo replication, and per-
component tuning. See https://docs.gitlab.com/charts/ for the complete reference.

---

## S3 Connection Secret

GitLab uses a `connection` secret (YAML format matching fog-aws) for object store auth.
The secret must be pre-created in Kubernetes or via Omnistrate secrets:

```yaml
# Connection secret (base64-encoded YAML in the K8s secret at key `connection`):
provider: AWS
region: us-east-1
use_iam_profile: true   # Use EKS IRSA/EC2 instance role — no static credentials needed
```

With IRSA or EC2 instance roles the chart can access S3 buckets without static credentials.
The Omnistrate `$secret.GITLAB_S3_CONNECTION` approach also works (store the YAML string as a secret).
