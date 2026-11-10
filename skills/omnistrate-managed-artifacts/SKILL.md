---
name: omnistrate-managed-artifacts
description: Inspect Omnistrate-managed amenity releases, Base Amenities release policies, private ECR synchronization, and provider-account public ECR publication; guide explicitly requested policy changes and diagnose BYOC-K8s install-kit artifact readiness. Not application image publishing, custom Helm artifacts, air-gapped packaging, or a deployment/agent upgrade workflow.
---

# Managed Artifact Releases

Use `omnistrate-ctl` (alias `omctl`) by default. Use equivalent MCP tools only
when the user asks for MCP. This workflow concerns Omnistrate-managed artifacts,
not a product's application images, custom amenities, or uploaded Helm/Terraform
source artifacts.

## Establish scope and availability

- Identify the intended Omnistrate API environment and SaaS Provider organization
  before authenticated inspection. Existing login state is not permission to
  inspect another organization, account, or live cluster.
- Check local command availability with `omnistrate-ctl managed-artifact --help`.
  Public inspection additionally requires `sync list --help` to include
  `--registry-type` and `--destination-account-id`. Help needs no login.
- Release/policy commands and private sync inspection require private managed
  artifact access. Public publication inspection has independent organization
  access. CLI availability does not prove backend routes or feature access.
- Root, Admin, Service Operator, Service Editor, and Service Reader can inspect;
  policy updates require Root, Admin, Service Operator, or Service Editor.
- Default to inspection. Ask for exact scope and action-time confirmation before
  a policy update, IAM/CloudFormation change, installation, or live rollout.
  A request to inspect readiness does not authorize any of those actions.

Merged source is not deployment evidence. Consult local help and, when needed,
`omctl docs search "managed artifact releases" --limit 15` for target-platform
documentation. A missing guide is not proof the feature is unsupported; report
backend availability as unverified when the requested inspection cannot confirm it.

## Keep selection, delivery, and installation separate

| Evidence | What it establishes |
|---|---|
| `release list` / `release describe` | Published release and managed amenity inventory |
| `policy describe` | Selection for one organization/environment/cloud template |
| Private `sync list` / `sync describe` | Private delivery to an execution provisioner |
| `sync list --registry-type public_ecr` | Public delivery to a provider AWS account |
| Cell configuration and lifecycle/workflow results | Application to a particular cell |

`READY` is registry readiness, not installed state. `effectiveBundleVersion` is
template selection, not the version running in a cell. Automatic runtime selection
can lag the newest published release while the relevant private/public copy is
unready. Do not turn a release pin into an unrequested upgrade or rollback.

## Inspect releases and registry records

Run only the commands needed for the requested scope:

```bash
omnistrate-ctl managed-artifact release list --limit 20 --output json
omnistrate-ctl managed-artifact release describe \
  --bundle-version <bundle-version> --output json

# Omitted registry selection inspects PRIVATE_ECR only.
omnistrate-ctl managed-artifact sync list \
  --bundle-version <bundle-version> --output json
omnistrate-ctl managed-artifact sync describe --id <sync-id> --output json

omnistrate-ctl managed-artifact sync list \
  --registry-type public_ecr \
  --destination-account-id <12-digit-provider-aws-account-id> \
  --bundle-version <bundle-version> --output json
omnistrate-ctl managed-artifact sync describe --id <publication-id> --output json
```

- `bundleVersion` (for example `r0000020`) is a release identifier, not a chart
  version or container tag. Use values returned by the API rather than inventing
  releases. `amenityName` identifies the managed amenity.
- `target.id` is the execution provisioner; `--target-id` is not a customer cell
  ID. Public records can lack a target before assignment.
- `destination.accountId` is a 12-digit AWS account ID; for public ECR it is the
  provider destination, independently of the worker's `target.accountId`.
  Combining account and target filters requires both to match.
- Private IDs start with `spabs-`; public publication IDs start with `sppap-`.
  Both use `sync describe --id`. Copy destination references/registry aliases
  from the response; do not synthesize them from a guessed prefix or tag.
- Release/private-sync counts cover managed amenities, not the internal catalog.
  Public publication has its own two-artifact inventory: the dataplane-agent
  chart (`helm-chart/dataplane-agent-chart`) and image
  (`container-image/chart/dataplane-agent-chart/image`). It does not publish
  product images or the Terraform executor.
- Lists default to 20 results; `--limit` accepts 1–100. Use JSON for automation.
  Pass `nextPageToken` unchanged with `--next-page-token` and the same organization,
  registry, account, release, status, target, and RFC3339 time filters. Discard it
  when scope changes. Mutable sync pages are not an atomic snapshot or total.
- An empty list does not prove older-backend support for registry/account filters.
  A missing record, forbidden access, and a successful empty result differ.

## Describe or change release policy

Both scope flags are required. Use `--environment-type global` for the default
GLOBAL template unless the user intends an enabled environment-specific template.
Other environment types are `dev`, `qa`, `staging`, `canary`, `prod`, and `private`.
Cloud values are `aws`, `azure`, `gcp`, `nebius`, `oci`, and `byoc-onprem`.
The lookup is exact: `prod` does not fall back to `global`, and `global` does not
update every environment. These flags do not change the API host used at login.

```bash
omnistrate-ctl managed-artifact policy describe \
  --environment-type global --cloud-provider aws --output json
```

`autoUpgrade=true` means no stored pin. `preferredBundleVersion` is the stored
pin; `effectiveBundleVersion` is the newest published release in automatic mode
and can be absent if none is published. Pinning additionally requires the selected
cloud's managed-consumption access; CTL forwards supported clouds and the API
enforces access. Clearing a pin remains possible after pinning access is revoked.

Only after the user confirms the exact template and policy change:

```bash
# Pin a published release. Check the relevant registry copy first.
omnistrate-ctl managed-artifact policy update \
  --environment-type <environment-type> --cloud-provider <cloud-provider> \
  --auto-upgrade=false --preferred-bundle-version <bundle-version> --output json

# Resume automatic selection and clear the pin.
omnistrate-ctl managed-artifact policy update \
  --environment-type <environment-type> --cloud-provider <cloud-provider> \
  --auto-upgrade=true --output json
```

The `--auto-upgrade` flag must be explicit. Do not combine `true` with a preferred
release. With `false`, omitting the preferred version retains an existing pin or
freezes the current effective published release; freezing fails if none exists.
An update can enqueue private synchronization but does not certify readiness or
apply changes to installed cells. Re-describe the policy afterward. There is no
independent public-ECR pin.

## BYOC-K8s artifact delivery and install kits

Do not confuse connected `byoc-onprem` with an air-gapped installer. Copy the chart
reference/version, image values, and registry authentication steps from a fresh
generated kit; never replace them with hardcoded GHCR/ECR references.

| Installer path | Policy and readiness |
|---|---|
| Signed private installer | `byoc-onprem` policy; selected provisioner's private copy must be `READY`. Missing/unready copies fail kit generation, without public/GHCR fallback. |
| Legacy installer with public publication access | Effective **AWS** policy; automatic mode selects the newest eligible `READY` public publication in the provider destination account. A pin requires that exact `READY` copy. |
| Legacy installer without public publication access | Legacy default public chart/image path remains in use. |

Private kits contain short-lived pull-only ECR credentials; their download URLs
are account-bound. Treat kits and signed URLs as credential material. Re-download
before reinstalling if credentials may have expired. Do not log them, commit them,
or paste them into a support report. Installation creates/updates the agent
image-pull Secret and requires separate authorization for the target cluster.

Allow outbound HTTPS to the generated registry and its download hosts as well as
the control plane. Public ECR pulls are anonymous but still need public egress;
private ECR VPC endpoints do not make public URLs reachable. Provider permissions,
organization feature access, and registry readiness are independent prerequisites.

For private managed consumption, provider-minted pull credentials are the
authorization source. A customer-account repository/IAM grant is a best-effort
backup, not a prerequisite for selecting a `READY` release; do not prescribe an
IAM change solely because that backup grant is absent. Public-reference fallback
requires a permitted public-egress path: endpoint-only cells with public egress
disabled reject it. The PrivateLink flag alone is not that restriction; eligible
PrivateLink consumers with public egress can retain the selected release through
public references after a recognized permission denial, including with a pin.
This does not relax the signed private installer's no-fallback requirement.

During ordinary public-path amenity reconciliation, no automatic `READY` copy
skips only the optional agent self-upgrade and preserves the installed agent.
Explicit updates and pinned-release failures remain errors. An explicitly
requested agent version must match the selected public managed release.

## Diagnose without changing delivery state

- Record statuses: `PENDING`, `IN_PROGRESS`, `READY`, `FAILED`, `SKIPPED`.
  Per-artifact statuses: `PENDING`, `READY`, `FAILED`. Clients must tolerate new
  response values; documented filter values remain the accepted inputs.
- Completed/failed counts describe artifact results; the remainder is not
  necessarily in progress. A failed record can contain successful artifacts.
- A never-established private target's recognized ECR permission denial can be
  `SKIPPED`, allowing eligible public-egress consumers to use public references.
  Later denials after successful private delivery remain failures. `SKIPPED` is
  not proof that private ECR works.
- Inspect sanitized `failureCategory`/`failureMessage` and, for public copies,
  source/destination references and digests. Public `READY` requires both approved
  artifacts and verified destination digests matching their release sources.
- `sync describe` can refresh known workflow state, so it may be newer than a
  persisted-state list. Neither command is a retry, resync, publish, or cancel
  operation. Do not retry workflows or modify IAM to make inspection succeed.
- If intervention is needed, report the release, registry kind, destination,
  record ID, execution target if present, and sanitized failure category. Do not
  infer a specific customer-VPC fault from a generic failure category.
- Investigate installed cell state only when that target and access are requested.
  Template sync/apply operations are separate live changes needing confirmation.

AWS provider onboarding uses `EnableArtifactECRPull` for private chart/image reads,
and independent `EnablePublicArtifactPublication` / `EnablePrivateArtifactPublication`
publisher controls. Provider onboarding defaults these controls on; customer
onboarding does not grant the provider-only policies. Opting out of public
publishing does not revoke already-public artifacts or disable private delivery.
Existing accounts may need a separately approved onboarding-stack update.
