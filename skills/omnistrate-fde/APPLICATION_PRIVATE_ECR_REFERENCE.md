# Application images and charts from private Amazon ECR

Use this reference when a connected Omnistrate workload consumes an
application image or Helm OCI chart from the service provider's private Amazon
ECR registry. It covers AWS, GCP, Azure, and connected BYOC-K8s (`byoc-onprem`)
targets.

This reference is only for application charts and images. Generic customer
registries and air-gapped installer image copying use different flows.

## Platform contract

For this application-private-ECR flow, Omnistrate:

- creates `artifacts-pull-secret` in every Omnistrate-managed namespace on the
  participating connected deployment cell, including namespaces that already
  exist and namespaces created later;
- refreshes the Secret automatically so workloads do not depend on a static ECR
  token;
- exposes the stable Secret name through
  `$sys.deployment.imagePullSecretName` when rendering each application; and
- keeps the Secret contents platform-owned. Plans consume only the name and
  never receive or persist registry credentials.

The system parameter resolves to the Kubernetes Secret **name**, not its data.
Workload Pods and Helm hooks must still reference that name explicitly;
Omnistrate does not rewrite arbitrary customer Pod or ServiceAccount specs.

Use the syntax required by the rendering context:

| Context | Correct reference |
|---|---|
| Helm `chartValues`, including Kubernetes manifests embedded as chart values | `$sys.deployment.imagePullSecretName` |
| Values inside a `layeredChartValues` layer | `$sys.deployment.imagePullSecretName` |
| Kustomize source YAML/TOML files | `{{ $sys.deployment.imagePullSecretName }}` |

In Helm, only `layeredChartValues.scope` keys use `{{ ... }}`. The values inside
the selected layer retain the ordinary bare Helm `chartValues` form.

## Before writing the plan

1. Confirm the ECR registry belongs to the provider-side AWS account configured
   for the plan and that the chart/image repository is inside the authorized
   repository scope. The namespace credential is intentionally not general ECR
   access; the supported provider-managed layout is under `artifacts/*`.
2. Confirm the relevant application-private-ECR capability is enabled for the
   provider. Do not toggle feature access as part of onboarding. Ask the
   provider administrator or Omnistrate support when the effective state is
   unknown.
3. Verify `$sys.deployment.imagePullSecretName` exists with:

   ```bash
   omctl docs system-parameters -o json
   ```

4. Do not create a static `aws ecr get-login-password` Secret, copy a token
   between namespaces, or put ECR credentials in `$secret.*`. Omnistrate owns
   creation and rotation of the namespace pull Secret.

The ECR account and region come from the provider/provisioner registry source,
not from the consumer dataplane region. A GCP, Azure, or AWS workload may pull
from an ECR registry in a different region.

## Authentication across target clouds

Omnistrate-minted namespace credentials are the default application-image path
for AWS, GCP, Azure, and connected BYOC-K8s. The plan explicitly references
`$sys.deployment.imagePullSecretName` on every supported target.

Do not expose an authentication-mode choice to end customers. Provider
bootstrap permissions and credential minting are platform
implementation details—not customer API parameters or chart values.

The rendered Secret name is `artifacts-pull-secret`, but plans should use the
system parameter rather than depending on the concrete name.

Omnistrate does not mutate arbitrary customer Pods or ServiceAccounts to add
the Secret. Every Pod that pulls privately—including Helm hooks—must carry the
reference. Init containers use the enclosing Pod's `imagePullSecrets`.

## Helm ServicePlanSpec

For a private ECR OCI chart, omit `authProvider`; Omnistrate resolves chart
credentials at deployment time. Application images inside the chart are a
separate pull and must be wired through the chart's values.

```yaml
helmChartConfiguration:
  chartName: redis
  chartVersion: 22.0.7
  chartRepoName: provider-private-ecr
  chartRepoURL: oci://<PROVIDER_ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/artifacts/charts
  # authProvider: omit for private ECR
  chartValues:
    image:
      registry: <PROVIDER_ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com
      repository: artifacts/app/redis
      tag: <PINNED_TAG>
      pullPolicy: Always
      pullSecrets:
        - "$sys.deployment.imagePullSecretName"
```

Use the chart's actual pull-secret value path; `image.pullSecrets` is only a
common example. If the chart creates hook Pods separately, wire those too:

```yaml
spec:
  imagePullSecrets:
    - name: "$sys.deployment.imagePullSecretName"
```

When a plan targets only AWS, GCP, Azure, and connected BYOC-K8s, the common
`chartValues` block above is intentionally valid for every target because the
Secret is created and rotated in every managed namespace. No cloud or
end-customer auth-mode selector is required.

If the same Helm resource also targets a cloud outside this flow, do not apply
the pull Secret globally. Replace `chartValues` with `layeredChartValues` and
scope the pull-secret value to each supported target. Helm can select these
values at runtime by cloud:

```yaml
layeredChartValues:
  - scope:
      "{{ $sys.deploymentCell.cloudProviderName }}": "aws"
    values:
      image:
        pullSecrets:
          - $sys.deployment.imagePullSecretName
  - scope:
      "{{ $sys.deploymentCell.cloudProviderName }}": "gcp"
    values:
      image:
        pullSecrets:
          - $sys.deployment.imagePullSecretName
  - scope:
      "{{ $sys.deploymentCell.cloudProviderName }}": "azure"
    values:
      image:
        pullSecrets:
          - $sys.deployment.imagePullSecretName
  - scope:
      "{{ $sys.deploymentCell.cloudProviderName }}": "byoc-onprem"
    values:
      image:
        pullSecrets:
          - $sys.deployment.imagePullSecretName
```

`chartValues` and `layeredChartValues` are mutually exclusive. Keep all other
required chart values inside the selected structure; the example isolates only
the pull-secret decision.

## Kustomize ServicePlanSpec

Kustomize does not have Helm's `layeredChartValues`. The plan selects an overlay
through `kustomizeConfiguration.kustomizePath`. Because the minted Secret is the
default on AWS, GCP, Azure, and connected BYOC-K8s, those targets can share one
private-ECR overlay:

```yaml
kustomizeConfiguration:
  kustomizePath: /kustomize/private-ecr
  gitConfiguration:
    repositoryUrl: https://github.com/<org>/<repo>.git
    reference: refs/tags/<version>
```

If a repository keeps both private-ECR and non-private overlays, select the
path while building the plan (or publish separate plan variants). Do not expect
Kustomize to choose the path dynamically at runtime, and do not expose the
overlay or authentication choice as an end-customer parameter. Helm plans can
instead use the cloud-scoped `layeredChartValues` pattern above.

Kustomize source files use mustache-style rendering for system parameters. In
the selected private-ECR overlay:

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      imagePullSecrets:
        - name: "{{ $sys.deployment.imagePullSecretName }}"
      containers:
        - name: app
          image: <PROVIDER_ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/artifacts/app/image@sha256:<DIGEST>
          imagePullPolicy: Always
```

Do not use the bare unrendered string `$sys.deployment.imagePullSecretName`
inside a Kustomize YAML file; use `{{ ... }}` there. Continue using ordinary
Kustomize namespace rendering such as `namespace: "{{ $sys.id }}"` when
required.

If rendering reports `missing kustomize file references` for
`$.deployment.imagePullSecretName`, the syntax was recognized but the system
parameter was absent from the render context. Do not replace it with static ECR
credentials. Verify the effective application-private-ECR capability and the
control-plane version, then inspect the rendered parameters.

## Compose and other registries

Do not copy this namespace-Secret pattern into a Compose spec: Compose does not
expose the Pod `imagePullSecrets` field. Use
`x-omnistrate-image-registry-attributes` for Compose registry authentication as
documented in `COMPOSE_ONBOARDING_REFERENCE.md`.

Likewise, this flow does not automatically cover arbitrary AWS ECR paths, GCP
Artifact Registry, Azure Container Registry, GHCR, Docker Hub, or a customer's
private registry. Use that registry's supported credential mechanism unless
the provider has explicitly onboarded it into the application-private-ECR
flow.

## Validation

For each enabled target cloud:

1. Deploy the private application image as the initial workload—do not use a
   public bootstrap image and switch later.
2. Require the Pod to be Running and Ready with the exact expected digest.
3. Confirm Pods on every supported target explicitly reference the rendered
   namespace Secret.
4. Trigger a controlled Deployment/StatefulSet template rollout and require a
   new Pod UID with the same private digest and `imagePullPolicy: Always`. This
   proves another authenticated pull without assuming that an application
   replica count creates a new physical node.
5. If claiming credential renewal, run a test beyond the ECR token lifetime.
   An immediate replacement-Pod pull is not a token-expiry soak.

Do not treat API `RUNNING` alone as evidence. Do not infer a new node from an
Omnistrate replica count: multiple Pods can share one node.

## Out of scope

- `BYOCPrivateRegistry` is a legacy path and is not a prerequisite here.
- Air-gapped installer registry copying follows `ONPREM_INSTALLER_REFERENCE.md`,
  not this connected namespace-credential flow.
