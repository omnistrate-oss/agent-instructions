---
name: omnistrate-managed-artifacts
description: Inspect Omnistrate-managed amenity releases, Base Amenities release policies, and private ECR synchronization; guide explicitly requested policy changes, automatic/manual private-publication settings, and single-sync copy (with customer vet/sign hooks), verification, or reconcile actions. Not application image publishing, custom Helm artifacts, BYOC-K8s agent installation, air-gapped packaging, or a deployment/agent upgrade workflow.
---

# Managed Artifact Releases

Use `omnistrate-ctl` (alias `omctl`) by default. Use equivalent MCP tools only
when the user asks for MCP; `sync copy` has no MCP tool. This workflow concerns Omnistrate-managed artifacts,
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
  access.
- Root, Admin, Service Operator, Service Editor, and Service Reader can inspect;
  policy updates and `sync copy`, `sync refresh-status`, or `sync reconcile`
  require Root, Admin, Service Operator, or Service Editor.
- Default to inspection. Ask for exact scope and action-time confirmation before
  a policy update, sync copy/refresh-status/reconcile, account private-publication
  setting change, IAM/CloudFormation change, or live rollout. A request to inspect readiness does not
  authorize any of those actions.

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
pin; `effectiveBundleVersion` is the newest published release whose private sync
is `READY` on every eligible provisioner in the organization, and is absent if no
such release exists. A stored pin that is not `READY` is reported without
`preferredBundleVersion` or `effectiveBundleVersion`. Pinning additionally
requires the selected cloud's managed-consumption access; CTL forwards supported
clouds and the API enforces access. Clearing a pin remains possible after pinning
access is revoked.

Only after the user confirms the exact template and policy change:

```bash
# Pin a published release whose private sync is READY; the API rejects others.
omnistrate-ctl managed-artifact policy update \
  --environment-type <environment-type> --cloud-provider <cloud-provider> \
  --auto-upgrade=false --preferred-bundle-version <bundle-version> --output json

# Resume automatic selection and clear the pin.
omnistrate-ctl managed-artifact policy update \
  --environment-type <environment-type> --cloud-provider <cloud-provider> \
  --auto-upgrade=true --output json
```

The `--auto-upgrade` flag must be explicit. Do not combine `true` with a preferred
release. With `false`, omitting the preferred version retains an existing `READY`
pin or freezes the newest `READY` release; freezing fails if none exists.
Enabling auto-upgrade can enqueue private synchronization of the newest published
release, but the effective release changes only after that copy is `READY`. An
update does not apply changes to installed cells. Re-describe the policy afterward.

## Private managed-artifact consumption

For private managed consumption, provider-minted pull credentials are the
authorization source. A customer-account repository/IAM grant is a best-effort
backup, not a prerequisite for selecting a `READY` release; do not prescribe an
IAM change solely because that backup grant is absent. Public-reference fallback
requires a permitted public-egress path: endpoint-only cells with public egress
disabled reject it. The PrivateLink flag alone is not that restriction; eligible
PrivateLink consumers with public egress can retain the selected release through
public references after a recognized permission denial, including with a pin.

The BYOC-K8s signed agent installer (install kits, signed download URLs, and kit
credentials) is out of scope here; use the `omnistrate-fde` skill's
`BYOC_K8S_REFERENCE.md`. This skill only answers whether the `byoc-onprem`
release and its private sync are `READY`.

## Diagnose without changing delivery state

- Record statuses: `PENDING`, `IN_PROGRESS`, `READY`, `FAILED`, `SKIPPED`,
  `MANUAL`. Per-artifact statuses: `PENDING`, `READY`, `FAILED`. Clients must
  tolerate new response values; documented filter values remain the accepted
  inputs.
- Completed/failed counts describe artifact results; the remainder is not
  necessarily in progress. A failed record can contain successful artifacts.
- A recognized private-ECR permission denial makes the record `SKIPPED` when the
  target is no longer an eligible provisioner, `MANUAL` when the account's applied
  `EnablePrivateArtifactPublication` setting is disabled or unrecorded, and
  `FAILED` otherwise. `MANUAL` is never retried automatically, and enabling the
  setting alone does not start a copy. Neither `SKIPPED` nor `MANUAL` proves that
  private ECR works.
- Inspect sanitized `failureCategory`/`failureMessage`, artifact results, and
  source/destination references and digests. Use the record status for readiness
  rather than treating a completion count or timestamp as proof.
- `sync describe` can refresh known workflow state, so it may be newer than a
  persisted-state list. Neither inspection command is a retry, resync, publish,
  or cancel operation. Do not retry workflows or modify IAM to make inspection
  succeed.
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

## Automatic or manual private publication

The account governance control `privateArtifactPublicationEnabled` decides who
copies managed artifacts into a SaaS Provider AWS account's private ECR. It applies
only to AWS accounts that are not BYOA. Enabled (default for new accounts): new
records are `PENDING` and Omnistrate copies them. Disabled: new records are
`MANUAL` and the provider copies, optionally vetting and signing first.

Change it only when the user explicitly requests it for an exact account, and
confirm immediately before running:

```bash
omnistrate-ctl account update <account-name-or-id> --private-artifact-push-enabled=false
omnistrate-ctl account update <account-name-or-id> --private-artifact-push-enabled=true
```

- Always use `=` with the value. Saving puts the account in `PENDING_UPDATE`.
  The setting applies only after the existing CloudFormation stack is updated to
  the matching `EnablePrivateArtifactPublication` value and Omnistrate verifies
  it. Never create a new stack; the stack update is a
  separate IAM change needing its own approval.
- The command waits and prints the next step; `--skip-wait` returns immediately.
  Confirm the applied value with `omnistrate-ctl account describe <account>`.
- Changing the setting does not retry existing records. `MANUAL` records stay
  `MANUAL` after enabling; each needs an explicitly requested `sync reconcile`.

## Act on one private sync

Run these only when the user explicitly requests the action for an exact
`spabs-` record, and confirm immediately before running. Each acts on that record
and its exact bundle version; none retries other records or releases.

```bash
# MANUAL only: copy by digest into the destination account, then verify.
omnistrate-ctl managed-artifact sync copy --id <sync-id> \
  --aws-profile <destination-account-profile>

# MANUAL only: verify a customer-populated destination; never copies.
omnistrate-ctl managed-artifact sync refresh-status --id <sync-id>

# MANUAL, FAILED, SKIPPED, or READY: request one platform copy and verification.
omnistrate-ctl managed-artifact sync reconcile --id <sync-id>
```

- `sync copy` is CLI-only: it runs operator-selected local hook executables with
  the CLI's AWS credentials, so the MCP server does not expose it. Never
  substitute another tool for it; ask the user to run it locally if the CLI is
  unavailable. `refresh-status` and `reconcile` have MCP equivalents.
- `sync copy` reads `manualCopyPlan` from `sync describe` and refuses non-`MANUAL`
  records. It needs a destination AWS profile that can describe, create, push to,
  and untag ECR repositories, plus local Docker credentials for private sources.
  Never alter the plan's prefix, relative path, version, or digest. It does not
  manage repository policies; other consumer accounts need separate pull grants.
- Copy lifecycle: stage every artifact by digest to a `manual-*` tag (creating
  repositories and checking digests/chart checksums), run the vetter for every
  staged artifact, then the signer for every artifact, and only then publish the
  version tag and `<version>-sha256-<16 hex>` alias, remove staging tags, and
  request `refresh-status`. If that final status request fails, run
  `refresh-status` separately.
- Hook events: each `--vetter`/`--signer` executable runs once per staged
  artifact, directly (no shell or arguments), with one JSON object on stdin:
  `artifactKey`, `sourceRef`, `destinationRef` (staging tag), `destinationDigest`,
  `destinationRegion`, and `awsProfile` (when set). `AWS_REGION`,
  `AWS_DEFAULT_REGION`, and `AWS_PROFILE` are set for the hook. With
  `--aws-profile`, the hook also receives that profile's resolved credentials
  (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and, when present,
  `AWS_SESSION_TOKEN`/`AWS_CREDENTIAL_EXPIRATION`) in place of inherited AWS
  credential variables, so it authenticates as the same identity as the copy;
  hooks should use the default credential chain rather than select another
  profile. Hook output goes to stderr. Exit `0` accepts; non-zero stops before any final tag is published,
  leaves staging tags for inspection, and keeps the record `MANUAL`. Hooks must
  act on `<destinationRef without :tag>@<destinationDigest>`, not the staging
  tag, and be safe to repeat. Use the `artifactKey` prefix (`container-image/`
  or `helm-chart/`) to choose image-only checks. The vetting and signing tools
  are the customer's choice; do not assume or install them.
- Re-running `sync copy` is safe: artifacts whose version tag already resolves to
  the planned digest are skipped with their hooks; the rest reuse matching
  staging tags and run the hooks again. The standalone `omnistrate-artifact-sync`
  runner (`--plan <sync describe JSON>`) does the same without calling the API;
  follow it with `refresh-status`.
- `refresh-status` promotes `MANUAL` to `READY` only when every artifact's version
  tag resolves to the release digest; otherwise the record stays `MANUAL` with
  per-artifact results. It does not verify cross-account repository policies.
- `reconcile` requires that automatic private publication is not disabled and
  that the target remains eligible. `MANUAL`, `FAILED`, and `SKIPPED` move to
  `IN_PROGRESS`, become `READY` on success, and restore their previous status
  and artifact results on failure. `READY` stays `READY`: success refreshes its
  results and failure leaves it unchanged. `IN_PROGRESS` and an active `READY`
  republish are rejected. Follow the result with `sync describe`.
- The CLI sends `refresh-status` and `reconcile` exactly once; it never retries
  them automatically. After a timeout, gateway error, or dropped connection, the
  action may already have taken effect: run `sync describe` before anything else
  and repeat only if the record shows it did not, with fresh confirmation. A
  `409 invalid_state` following such a failure can mean the first attempt
  succeeded (for example, the record is now `IN_PROGRESS` or `READY`).
- Treat a rejection as state to report, not a reason to change IAM, account
  settings, or workflows.
