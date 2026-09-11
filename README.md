# gitops_homeease

GitOps source of truth for the HomeEase platform, deployed to **two
independent clusters — AKS (Azure) and EKS (AWS)** — each with its own
ArgoCD install. Companion to `app_Homeease` (application code + CI, which
already builds and pushes images) and `Infrastruture_Homeease` (Terraform).

No Helm here. Every Kubernetes manifest is plain, literal YAML —
[Kustomize](https://kustomize.io) (built into `kubectl` and natively
understood by ArgoCD) handles the small per-cloud/per-environment
differences via patches, not a templating language.

## Repo layout

```
apps/                        one folder per service (frontend, backend, admin-backend, payment-service)
  <service>/
    base/                    the REAL Kubernetes manifests — Deployment, Service, ServiceAccount,
                              NetworkPolicy, HPA, PDB, and (where public) Ingress. Open any file here
                              and it's exactly what `kubectl get -o yaml` would show you — no {{ }},
                              no includes, nothing to mentally expand.
    overlays/
      azure/dev/             what's DIFFERENT on AKS-dev: image registry (ACR), hostnames, and
                              (payment-service only) the Azure Key Vault SecretProviderClass
      aws/dev/                same, for EKS-dev: image registry (ECR), hostnames, and the AWS
                              Secrets Manager SecretProviderClass

argocd/                      ArgoCD config — completely separate per cloud, because each cloud
                              runs its OWN ArgoCD on its OWN cluster
  azure/
    bootstrap/                root-app.yaml (the one manual kubectl apply) + the AppProject +
                              one Application per service + one Application per platform/ component
    projects/                 the `homeease` AppProject that scopes what AKS's 4 service Applications
                              may touch
  aws/                        identical shape, pointed at EKS and apps/*/overlays/aws/dev instead

platform/                    cluster-wide components' VALUES only (kube-prometheus-stack, Loki, Alloy —
                              done; ingress-nginx, cert-manager — placeholder). UNCHANGED in this
                              restructure — see platform/README.md. Shared as-is by both clouds; each
                              cloud's argocd/<cloud>/bootstrap/ has its own Application pointing at the
                              same values file, since it's two independent ArgoCD installs.
```

## Why Kustomize instead of the old Helm library chart

The previous version of this repo had a `charts/common` Helm **library**
chart full of `{{ include "common.xxx" . }}` calls, and every service's
own `templates/*.yaml` was a one-line file that just called into it. It
worked, but you had to open 2-3 files across 2 directories to see what a
single Deployment actually contained, and Helm's library-chart values
scoping (`.Values` in the library chart is never actually loaded — see the
old `charts/common/values.yaml` comment) tripped up review more than once.

Kustomize's model is the opposite: `apps/<service>/base/*.yaml` **is** the
manifest, full stop. The only per-cloud/per-environment differences —
container image, hostnames, and (for the one service that needs it) which
cloud's secret store to read from — live in a handful of small,
explicit `overlays/<cloud>/<env>/kustomization.yaml` patches. Nothing is
inferred; every difference between AKS-dev and EKS-dev is one `git diff`
between two small files away.

## Why plain Applications instead of an ApplicationSet

4 services × 1 environment × 2 clouds is 8 Application objects today.
That's few enough to hand-write and read individually
(`argocd/<cloud>/bootstrap/0N-<service>.yaml`) rather than reason about a
generator's matrix expansion. If staging/prod get added later and the
count grows past what's comfortable to hand-write, that's the point to
introduce an ApplicationSet per cloud — not before.

## What's identical between AWS and Azure, and what isn't

**Identical** (all of `apps/<service>/base/`): the Deployment shape,
container security context, resource requests/limits, health probes,
Service, ServiceAccount, HPA, PDB, NetworkPolicy rules, and (where public)
Ingress path/backend. A service behaves the same way on both clouds.

**Different** (only in `apps/<service>/overlays/<cloud>/dev/`):
- container registry (ACR vs ECR) and image tag
- public hostnames
- for `payment-service` only: the `SecretProviderClass` provider (Azure
  Key Vault vs AWS Secrets Manager) and the workload identity mechanism
  on its ServiceAccount (Azure Workload Identity's `client-id` annotation
  vs AWS IRSA's `role-arn` annotation) — the two cloud secret stores have
  genuinely different APIs, so this is the one place cloud-specific code
  actually has to exist. Everything that reads the resulting secret (the
  Deployment's `envFrom`) is identical on both clouds.

## NetworkPolicy and Ingress — what you need on the cluster for these to work

`NetworkPolicy` objects are accepted by the Kubernetes API on *any*
cluster, but are only **enforced** if the CNI implements it:
- **AKS**: Azure CNI Overlay by itself only handles pod IP addressing.
  You must also turn on Azure NPM or Calico network policy at cluster
  creation.
- **EKS**: the default Amazon VPC CNI needs `ENABLE_NETWORK_POLICY=true`
  (v1.14+) or the Calico/Cilium add-on. Without one of those, `kubectl
  describe networkpolicy` will show the object but nothing is actually
  blocked.

Each service's `NetworkPolicy` defaults to deny-all-ingress except an
explicit allow list — see the comments in each `base/networkpolicy.yaml`
for exactly who's allowed to reach it and why.

`Ingress` objects need an ingress controller installed to do anything —
`platform/` has `ingress-nginx` as a placeholder (not yet installed on
either cluster; see `platform/README.md`). Every app's Ingress here
already sets `ingressClassName: nginx` and a `cert-manager.io/
cluster-issuer` annotation so both come alive automatically the moment
ingress-nginx and cert-manager are actually installed — nothing to edit
in `apps/` when that happens.

## How to bootstrap either cluster (once, by a human)

```bash
# Azure (AKS)
kubectl config use-context aks-homeease-dev
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd   # one-time, not GitOps-managed
kubectl apply -f argocd/azure/bootstrap/root-app.yaml

# AWS (EKS) — a completely separate ArgoCD, on a completely separate cluster
kubectl config use-context eks-homeease-dev
kubectl create namespace argocd
helm install argocd argo/argo-cd -n argocd
kubectl apply -f argocd/aws/bootstrap/root-app.yaml
```

ArgoCD can't install its own first Application — something has to create
the first one by hand, per cluster. After that, everything else
(AppProject, kube-prometheus-stack, Loki, Alloy, and the 4 service
Applications) is reconciled from this repo automatically, independently,
on each cluster.

```bash
kubectl get applications -n argocd
# expect: homeease-root, homeease-project, kube-prometheus-stack, loki, alloy,
#         frontend-dev, backend-dev, admin-backend-dev, payment-service-dev
```

## Rendering locally before you push

```bash
kubectl kustomize apps/backend/overlays/azure/dev
kubectl kustomize apps/backend/overlays/aws/dev
kubectl kustomize apps/payment-service/overlays/azure/dev   # includes the SecretProviderClass
```

Every `REPLACE-WITH-*` placeholder (image tag, Key Vault name, tenant ID,
AWS account ID/region, IAM role ARN, hostnames) needs a real value before
that overlay is synced for real — ArgoCD will happily apply the literal
placeholder string otherwise. Image tags are bumped by CI in
`app_Homeease` on every merge to main; the rest are one-time values from
Terraform outputs.

## Environments

Only `dev` exists today, on both clouds, and auto-syncs on every merge to
`main` (self-heal + prune on). To add `staging` or `prod`: copy an
existing `apps/<service>/overlays/<cloud>/dev/` folder to `.../staging/`,
adjust its `images:`/hostname/replica patches, and add a matching
`argocd/<cloud>/bootstrap/1N-<service>-staging.yaml` Application — same
mechanism, no new tooling needed. Once that Application doesn't get a
`syncPolicy.automated` block, a change sits as "OutOfSync" until a human
runs `argocd app sync` — that's the promotion gate for those environments.
