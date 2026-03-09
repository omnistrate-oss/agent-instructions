---
name: Closing Documentation Gaps
description: Systematically close documentation gaps tracked in the Omnistrate GitHub Project board. Fetches pending items, triages them, groups by topic, analyzes existing docs, writes documentation updates, creates draft PRs, and marks items as Done after confirmation. Works against the omnistrate/documentation repo using Material for MkDocs.
---

# Closing Documentation Gaps

## When to Use This Skill
- Closing documentation gaps tracked in the Omnistrate roadmap project board
- Creating or updating documentation for completed platform features
- Triaging project board items to determine what needs documentation
- Grouping related documentation tasks and creating consolidated PRs
- Marking documentation items as Done on the project board

## Overview

**Project Board**: https://github.com/orgs/omnistrate/projects/22/views/23

This skill works with two GitHub repos:
- **omnistrate/roadmap** — the project board with issues tracked in [GitHub Project #22, View 23 "Documentation tracker"](https://github.com/orgs/omnistrate/projects/22/views/23)
- **omnistrate/documentation** — the MkDocs documentation site (Material for MkDocs)

Each roadmap issue has a "Docs (+ API docs)" field that can be Pending, Done, or N/A. This skill processes Pending items for issues with status=Done (feature shipped but docs not updated).

## Workflow

### Phase 1: Fetch Pending Items

Fetch all project items where "Docs (+ API docs)" = "Pending" using `gh project item-list`:

```bash
gh project item-list 22 --owner omnistrate --format json --limit 1000
```

Parse the JSON output and filter for:
- `docs_status == "Pending"` (the field starting with "Docs")
- `status == "Done"` (feature is shipped)

Store the filtered list for processing. Show the user a summary: total items, by status, and how many remain unprocessed.

### Phase 2: Triage Items

For each pending item, classify it as:

1. **documentable** — Feature needs documentation updates (user-facing, has impact on docs)
2. **already-documented** — Feature is already covered in existing docs (verify by reading relevant files)
3. **not-applicable** — Internal work, PoCs, consulting, infrastructure fixes, security patches, or deprecated features that don't need public docs

**Auto-classify as not-applicable** items matching these patterns:
- PoC, consulting, discovery, investigation
- Internal infrastructure (remove argo, deprecate, enable in dev)
- Security vulnerability fixes (not feature docs)
- Specific customer engagements (Bytez, Liferay, FerretDB, DataRobot-specific)
- Cost/billing internal fixes
- Product demos, CI process changes

**Present the triage results** to the user and ASK for confirmation before proceeding. The user may override classifications.

### Phase 3: Group by Topic

Group documentable items by common topic. Use these topic categories:

| Topic | Keywords | Likely docs files |
|-------|----------|-------------------|
| snapshots-backups | snapshot, backup, restore, pitr | deployment-snapshots.md, pitr.md |
| billing-cost | billing, cost, payment, pricing, tax | billing.md, cost-insights.md |
| azure | azure, bootstrap azure | byoc.md, cloud-account-permissions.md |
| deployment-cells | deployment cell, amenities | deployment-cells.md |
| cli-ctl | ctl, cli, command | getting-started-with-ctl.md |
| api-spec | api param, compose spec, .env, parameter order | compose-spec.md, plan-spec.md, api-params.md |
| instance-management | instance, deployment, network type, deletion protection | Various operate-guides |
| helm-secrets | helm, secret, chart values | helm-charts-customize.md, secrets.md |
| networking | network, endpoint, vpc, custom network | customer-networks.md, private-networking.md |
| alerts-monitoring | alert, alarm, storage size, metrics | alarms.md |
| keda-autoscaling | keda, autoscaling | New page or runtime-guides |
| gpu-compute | gpu, slicing | gpu-accelerator-configuration.md, gpu-slicing.md |
| tags-labels | tag, instance tags | New section in operate-guides |
| customer-portal | portal, verification, offboarding, GDPR | customer-portal.md, account-onboarding.md |
| expressions | expression, evaluate | evaluate-expressions.md |
| oci-support | oci | New page or build-guides |
| mcp-llms | mcp, llms.txt | mcp-server.md |
| workflow | workflow, restart | troubleshooting.md or operate-guides |
| dryrun | dryrun, dry run | pipelines.md or plan.md |
| affiliation | affiliat | New section in tenant-management |

Items that don't match any topic go to "ungrouped" and are handled individually.

**Present groups** to the user and ASK for confirmation. The user may reorganize groups.

### Phase 4: Analyze and Write Documentation

For each group (one at a time, in priority order):

#### Step 1: Analyze
1. Fetch the issue body from omnistrate/roadmap for each issue in the group:
   ```bash
   gh issue view NUMBER -R omnistrate/roadmap --json body,title,labels
   ```
2. Read the existing documentation files that are relevant (identified in the grouping phase)
3. Determine what content needs to be added or updated
4. Present a summary to the user: what changes you plan to make and to which files

#### Step 2: ASK before creating PR
Always ask the user: "Should I create a draft PR for this group, mark items as already documented, or skip?"

#### Step 3: Create the draft PR
If approved:

1. **Ensure clean state on master**:
   ```bash
   git checkout master && git pull origin master
   ```

2. **Create a feature branch**:
   ```bash
   git checkout -b docs/GROUP_NAME
   ```

3. **Write documentation changes** following these rules:
   - Follow the documentation style guide (see Documentation Standards below)
   - Use American English, active voice, second person ("you")
   - Title case for h1/h2, sentence case for h3+
   - Always specify language for code blocks
   - Use Material for MkDocs admonition syntax (`!!! note`, `!!! warning`, etc.)
   - Use relative links for internal documentation
   - Place images in `/docs/images/`
   - Use `:white_check_mark:` instead of raw emoji in tables

4. **Handle shell-sensitive content carefully**:
   - Content with `$variable`, `{{ }}`, or special characters must be written using Python file operations, NOT bash heredocs or cat
   - Example:
     ```python
     python3 -c "
     content = '''... your markdown content ...'''
     with open('docs/path/to/file.md', 'w') as f:
         f.write(content)
     "
     ```

5. **Commit with proper format**:
   ```bash
   git add -A
   git commit -m "docs: GROUP_NAME documentation updates

   Related issues: #N1 #N2 #N3

   - #N1: Title
   - #N2: Title
   - #N3: Title

   Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
   ```

6. **Push and create draft PR**:
   ```bash
   git push -u origin docs/GROUP_NAME
   gh pr create --draft \
     --title "docs: GROUP_NAME documentation" \
     --body "## Documentation Update: GROUP_NAME

   ### Related Issues
   - https://github.com/omnistrate/roadmap/issues/N1
   - https://github.com/omnistrate/roadmap/issues/N2

   ### Changes
   - #N1: Title
   - #N2: Title

   ### Checklist
   - [ ] Content is technically accurate
   - [ ] Follows documentation style guidelines
   - [ ] Links are valid
   - [ ] Code examples are correct" \
     --base master \
     -R omnistrate/documentation
   ```

7. **Return to master**:
   ```bash
   git checkout master
   ```

### Phase 5: Mark Items as Done

After the PR is created, **ASK the user** before marking items as Done on the project board.

If approved, update via GraphQL mutation:

```bash
gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "PVT_kwDOBoTTdc4Anf6C"
    itemId: "ITEM_ID"
    fieldId: "PVTSSF_lADOBoTTdc4Anf6CzgfgnCc"
    value: { singleSelectOptionId: "15a97951" }
  }) {
    projectV2Item { id }
  }
}'
```

**Finding item IDs**: The item_id comes from the `gh project item-list` JSON output. Match by issue number.

**Option IDs**:
- Done: `15a97951`
- Pending: `788d81c2`
- N/A: `ee3532fd`

For non-applicable items, use the N/A option ID instead.

After marking, always share the issue link: `https://github.com/omnistrate/roadmap/issues/NUMBER`

## Project Board Reference

| Constant | Value |
|----------|-------|
| Project ID | `PVT_kwDOBoTTdc4Anf6C` |
| Docs field ID | `PVTSSF_lADOBoTTdc4Anf6CzgfgnCc` |
| Done option ID | `15a97951` |
| Pending option ID | `788d81c2` |
| N/A option ID | `ee3532fd` |
| Org | `omnistrate` |
| Roadmap repo | `omnistrate/roadmap` |
| Docs repo | `omnistrate/documentation` |
| Docs default branch | `master` |

## Documentation Standards

### Style Rules
- **Format**: Markdown with Material for MkDocs extensions
- **Language**: American English
- **Voice**: Active voice, second person ("you") for instructions
- **Headers**: Title case for h1/h2; sentence case for h3+
- **Code blocks**: Always specify language (```yaml, ```bash, ```json, etc.)
- **File naming**: Lowercase kebab-case for all markdown files
- **Images**: Place in `/docs/images/`, reference with relative paths
- **Links**: Use relative links for internal docs
- **Admonitions**: Use `!!! note`, `!!! warning`, `!!! tip`, `!!! danger`
- **Navigation**: Add new pages to `mkdocs.yml` nav section
- **Emoji in tables**: Use `:white_check_mark:` not raw ✅

### Terminology (Current → Deprecated)
Always use the correct terms:
- **SaaS Product** (not "Service", "SaaS Offer")
- **Plan** (not "Service Plan")
- **Resource** (not "Service Component")
- **SaaS Provider** (not "Service Provider")
- **Environment** (not "Service Environment")
- **Deployment Model** (not "Hosting Model")
- **Tenancy Type** (not "Deployment Model")
- **BYOC / Bring Your Own Cloud** (not "BYOA")
- **Customer Portal** (not "SaaS Portal")
- **Custom Network** (not "Customer Network")
- **BYOC Copilot** (not "On-Prem Copilot")
- **Container image** (not "Docker image")
- **Notification** (not "Events")
- **Alerts** (not "Alarm")

### Documentation Structure
```
docs/
├── getting-started/      # Onboarding, installation, quick starts
├── spec-guides/          # Compose spec, Plan spec
├── build-guides/         # Plans, resources, helm, terraform
├── runtime-guides/       # Sidecars, tagging, serverless, PITR
├── infra-guides/         # GPU, endpoints, blob storage
├── operate-guides/       # Alarms, troubleshooting, fleet dashboard
├── dev-ops-guides/       # Secrets, upgrades, pipelines, snapshots
├── fin-ops-guides/       # Billing, cost insights
├── governance-guides/    # RBAC, permissions, security
├── tenant-management/    # Portal, subscriptions, networking
└── usecases/             # BYOC, SaaS hosted
```

## Confirmation Gates

**CRITICAL**: This skill has mandatory confirmation points. NEVER proceed past these without user approval:

1. **After triage** — Show classification results, ask to confirm or override
2. **After grouping** — Show groups, ask to confirm or reorganize
3. **Before each PR** — Show planned changes, ask: create PR / mark as done / skip
4. **After each PR** — Ask before marking items as Done on project board

## Items Already Processed

These issues have already been processed in previous sessions and should be skipped:
#323, #238, #243, #359, #377, #201, #246, #385, #325, #337, #156, #157, #240, #223, #154,
#49, #77, #87, #76, #102, #90, #327, #339, #40, #54, #99, #100, #331, #336, #119, #134, #168, #174

## Error Handling

### Shell Expansion Issues
Content with `$`, `{{ }}`, or backticks causes shell expansion problems. Always use Python for writing content:
```bash
python3 -c "
content = '''your markdown here'''
with open('docs/path/file.md', 'w') as f:
    f.write(content)
"
```

### Edit Tool Whitespace
The edit tool may fail on files with trailing whitespace mismatches. Use Python file operations as a fallback.

### Branch Conflicts
If a branch already exists:
```bash
git checkout docs/GROUP_NAME
git rebase master
```

### Large Files
For spec files (compose-spec.md, plan-spec.md) that are very large, use targeted edits rather than rewriting the whole file. Use grep to find the insertion point first.
