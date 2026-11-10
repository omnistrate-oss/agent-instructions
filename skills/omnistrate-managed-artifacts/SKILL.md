---
name: omnistrate-managed-artifacts
description: Inspect Omnistrate-managed amenity releases, Base Amenities release policies, and private ECR synchronization; guide explicitly requested policy changes and diagnose signed private BYOC-K8s install-kit readiness. Not application image publishing, custom Helm artifacts, air-gapped packaging, or a deployment/agent upgrade workflow.
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
  Help needs no login. Check `sync list --help` for `--destination-account-id`
  before using the optional account filter.
- Release/policy commands and private sync inspection require private managed
  artifact access. CLI availability does not prove backend routes or feature
  access. Installer tasks additionally require the provider's signed private
  installer access.
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
| `deployment-cell describe` `current_managed_artifact_version` | Release currently serving a particular cell |
| Cell configuration and lifecycle/workflow results | Why a cell has or has not applied the selection |

`READY` is registry readiness, not installed state. `effectiveBundleVersion` is
template selection, not the version running in a cell; use the cell's
`current_managed_artifact_version` for that. Automatic runtime selection
can lag the newest published release while the relevant private copy is
unready. Do not turn a release pin into an unrequested upgrade or rollback.

## Inspect releases and registry records

Run only the commands needed for the requested scope:

```bash
omnistrate-ctl managed-artifact release list --limit 20 --output json
omnistrate-ctl managed-artifact release describe \
  --bundle-version <bundle-version> --output json

# Omitted registry selection inspects PRIVATE_ECR only. Public ECR publication
# (--registry-type public_ecr, sppap- IDs) is out of scope for this skill.
omnistrate-ctl managed-artifact sync list \
  --bundle-version <bundle-version> --output json
omnistrate-ctl managed-artifact sync describe --id <sync-id> --output json
```

- `bundleVersion` (for example `r0000020`) is a release identifier, not a chart
  version or container tag. Use values returned by the API rather than inventing
  releases. `amenityName` identifies the managed amenity.
- `target.id` is the execution provisioner; `--target-id` is not a customer cell
  ID.
- `destination.accountId` is the private destination's 12-digit AWS account ID.
  Combining account and target filters requires both to match.
- Private synchronization IDs start with `spabs-`; use `sync describe --id`.
  Copy destination references and registry hostnames from the response; do not
  synthesize them from a guessed prefix or tag.
- Release/private-sync counts cover managed amenities, not the internal catalog
  or the product's application artifacts.
- Lists default to 20 results; `--limit` accepts 1–100. Use JSON for automation.
  Pass `nextPageToken` unchanged with `--next-page-token` and the same organization,
  account, release, status, target, and RFC3339 time filters. Discard it
  when scope changes. Mutable sync pages are not an atomic snapshot or total.
- An empty list does not prove older-backend support for the account filter.
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
apply changes to installed cells. Re-describe the policy afterward.

## BYOC-K8s signed private install kits

Do not confuse connected `byoc-onprem` with an air-gapped installer. This workflow
uses the signed private installer and private managed-artifact access for the
SaaS Provider organization. The `byoc-onprem` template policy selects the release;
its private copy must be `READY` on the selected provider AWS provisioner. A
missing/unready copy fails kit generation without public-source fallback.

Copy the chart reference/version, image values, Helm authentication, and
image-pull Secret instructions from a fresh generated kit. Do not substitute a
hardcoded registry or tag. Use the generated
`result_params.byoc_onprem_install_command` when supplied: its download URL is
signed, expiring, and bound to the account configuration. Never reconstruct the
URL from an account ID or strip its signature/query parameters. If it has expired,
request a fresh kit/command through the authenticated customer-account workflow.

Private kits contain short-lived pull-only ECR credentials; their download URLs
are account-bound. Treat kits and signed URLs as credential material. Re-download
before reinstalling if credentials may have expired. Do not log them, commit them,
or paste them into a support report. Installation creates/updates the agent
image-pull Secret and requires separate authorization for the target cluster.

Allow outbound HTTPS to the generated private registry and its download hosts as
well as the control plane. Provider private-publication permissions, organization
feature access, and registry readiness are independent prerequisites.

For private managed consumption, provider-minted pull credentials are the
authorization source. A customer-account repository/IAM grant is a best-effort
backup, not a prerequisite for selecting a `READY` release; do not prescribe an
IAM change solely because that backup grant is absent. Public-reference fallback
requires a permitted public-egress path: endpoint-only cells with public egress
disabled reject it. The PrivateLink flag alone is not that restriction; eligible
PrivateLink consumers with public egress can retain the selected release through
public references after a recognized permission denial, including with a pin.
This does not relax the signed private installer's no-fallback requirement.

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
- Inspect sanitized `failureCategory`/`failureMessage`, artifact results, and
  source/destination references and digests. Use the record status for readiness
  rather than treating a completion count or timestamp as proof.
- `sync describe` can refresh known workflow state, so it may be newer than a
  persisted-state list. Neither command is a retry, resync, publish, or cancel
  operation. Do not retry workflows or modify IAM to make inspection succeed.
- If intervention is needed, report the release, private destination,
  record ID, execution target if present, and sanitized failure category. Do not
  infer a specific customer-VPC fault from a generic failure category.
- Investigate installed cell state only when that target and access are requested.
  `omnistrate-ctl deployment-cell describe <cell-id> -o json` reports
  `current_managed_artifact_version` (release serving the cell; pending/failed
  updates keep the previous value, permission fallback reports its resolved
  release) and `effective_managed_artifact_version` (template selection).
  Template sync/apply operations are separate live changes needing confirmation.

AWS provider onboarding uses `EnableArtifactECRPull` for private chart/image reads,
and `EnablePrivateArtifactPublication` for private publisher permissions. Provider
onboarding defaults these controls on; customer onboarding does not grant the
provider-only policies. Existing accounts may need a separately approved
onboarding-stack update.
