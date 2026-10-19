# Application images and charts from private Amazon ECR

Use this reference when a connected Omnistrate workload consumes an
application image or Helm OCI chart from the service provider's private Amazon
ECR registry. It covers AWS, GCP, Azure, and connected BYOC-K8s (`byoc-onprem`)
targets.

This reference is only for application charts and images. Generic customer
registries and air-gapped installer image copying use different flows.

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
   creation and rotation of the namespace pull Secret where Secret mode applies.

The ECR account and region come from the provider/provisioner registry source,
not from the consumer dataplane region. A GCP, Azure, or AWS workload may pull
from an ECR registry in a different region.

## Authentication by target cloud

| Target | Application-image authentication | Workload configuration |
|---|---|---|
| AWS BYOC, native mode | Customer node IAM plus provider ECR repository access | Do **not** attach a pull Secret. A Secret can mask broken native IAM. |
| AWS BYOC, namespace-Secret mode | Omnistrate-minted ECR credentials in the instance namespace | Explicitly reference `$sys.deployment.imagePullSecretName`. |
| GCP BYOC | Omnistrate-minted ECR credentials in the instance namespace | Explicitly reference `$sys.deployment.imagePullSecretName`. |
| Azure BYOC | Omnistrate-minted ECR credentials in the instance namespace | Explicitly reference `$sys.deployment.imagePullSecretName`. |
| Connected BYOC-K8s | Omnistrate-minted ECR credentials in the instance namespace | Explicitly reference `$sys.deployment.imagePullSecretName`. The public installer/agent bootstrap is a separate concern. |

The rendered Secret name is currently `artifacts-pull-secret`, but plans should
use the system parameter rather than depending on the concrete name.

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

For AWS native mode, omit these pull-Secret values so the test and runtime do
not silently fall back from node IAM to Secret authentication.

## Kustomize ServicePlanSpec

Kustomize source files use mustache-style rendering for system parameters. In
the Secret-enabled overlay:

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

Keep a separate AWS-native overlay with no `imagePullSecrets` entry. Do not use
the bare unrendered string `$sys.deployment.imagePullSecretName` inside a
Kustomize YAML file; use `{{ ... }}` there. Continue using ordinary Kustomize
namespace rendering such as `namespace: "{{ $sys.id }}"` when required.

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
3. Confirm Secret-mode Pods explicitly reference the rendered namespace Secret;
   confirm AWS-native Pods do not reference one.
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
