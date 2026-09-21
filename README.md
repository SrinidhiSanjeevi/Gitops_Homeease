# gitops_homeease

GitOps source of truth for the HomeEase platform, deployed today to one
live cluster — **AKS (Azure), `aks-homeease-dev`** — via its own ArgoCD
install. Companion to `app_Homeease` (application code + CI, which
builds, scans, and pushes images to ACR, then promotes the tag here —
see "How image tags get here" below) and `Infrastruture_Homeease`
(Terraform).

Every service ships as a real **Helm chart** under `charts/`. There is no
Kustomize tree in this repo — the original `apps/<service>/base` +
`overlays/<cloud>/<env>` layout was fully migrated to Helm (validated
33/33 rendered resources identical to the Kustomize output before
cutover); nothing under `apps/` exists anymore.

## Repo layout

```
charts/                      one Helm chart per service (frontend, admin-frontend, backend, admin-backend, payment-service)
  <service>/
    Chart.yaml
    values.yaml               cloud/environment-neutral defaults — no registry, no secrets, no hostnames
    values-azure-dev.yaml     the live AKS-dev overrides this repo's ArgoCD Applications actually use:
                              image tag, ingress host, Workload Identity clientId, Key Vault name/tenant
    values-demo.yaml          standalone values for `helm install` into a throwaway namespace/cluster,
                              independent of the live ArgoCD-managed release (see each file's own header
                              comment for what does and doesn't work standalone)
    templates/                Deployment, Service, ServiceAccount, HPA, PDB, NetworkPolicy, and (where
                              applicable) Ingress, SecretProviderClass, ServiceMonitor

argocd/
  azure/                      the ONLY live ArgoCD config today, on aks-homeease-dev
    bootstrap/                root-app.yaml (the one manual kubectl apply) + the AppProjects + one
                              Application per service + one Application per done platform/ component
    projects/                 homeease-appproject.yaml (scopes the 5 service Applications) and
                              platform-appproject.yaml (scopes kube-prometheus-stack/Loki/Alloy)
  _aws-disabled/              PARKED, not read by any live ArgoCD — see its own README.md. Every
                              Application here still points at the deleted `apps/*/overlays/aws/dev`
                              Kustomize tree and was never migrated to Helm; no EKS cluster was ever
                              deployed. Kept for reference, not wired into anything.

platform/                    cluster-wide components' Helm VALUES only (kube-prometheus-stack, Loki,
                              Alloy — done; ingress-nginx, cert-manager — placeholder, see
                              platform/README.md). Each component's Application lives in
                              argocd/azure/bootstrap/, under the `platform` AppProject, not `homeease`.

.github/workflows/            docs-check.yml — fails CI if a doc references a repo path that doesn't
                              exist (see below)
```

## Charts: what's identical and what differs between services

**Identical shape** across all five: Deployment (security context,
resource requests/limits, health probes), Service, ServiceAccount, HPA,
PDB, NetworkPolicy (default-deny ingress + explicit allow rules).

**Differs per service**, all expressed as chart templates + values, never
as separate overlay trees:
- `frontend`, `admin-frontend`, and `admin-backend` have a public
  `Ingress`; `payment-service` is internal-only by design and has no
  `ingress.yaml` template at all.
- `backend`, `admin-backend`, and `payment-service` mount secrets via
  `SecretProviderClass` (Azure Key Vault, gated by `secretProviderClass.
  enabled` and `workloadIdentity.enabled` in values) and export a
  `ServiceMonitor`; `frontend` needs neither.
- Azure AD Workload Identity `clientId` and Key Vault name/tenant are
  non-secret identifiers set per-environment in `values-<env>.yaml` —
  never in `values.yaml`, and never the secret contents themselves, which
  stay in Key Vault and are synced at runtime by the Secrets Store CSI
  driver.

## Why plain Applications instead of an ApplicationSet

5 services × 1 environment is 5 Application objects today, hand-written
and readable individually (`argocd/azure/bootstrap/0N-<service>.yaml`)
rather than a generator's matrix to mentally expand. If staging/prod get
added later and the count grows past what's comfortable to hand-write,
that's the point to introduce an ApplicationSet — not before.

## NetworkPolicy and Ingress — what you need on the cluster for these to work

`NetworkPolicy` objects are accepted by the Kubernetes API on any
cluster, but are only **enforced** if the CNI implements it — on AKS,
Azure CNI Overlay by itself only handles pod IP addressing; Azure NPM or
Calico network policy has to be turned on at cluster creation.

`Ingress` objects need an ingress controller to do anything.
`ingress-nginx` and `cert-manager` are `platform/` placeholders today
(not yet installed) — see `platform/README.md` for status. Every chart's
Ingress template already sets `ingressClassName: nginx` and a
`cert-manager.io/cluster-issuer` annotation so both come alive
automatically the moment those two are actually installed — nothing to
edit in `charts/` when that happens.

## How to bootstrap the cluster (once, by a human)

```bash
kubectl config use-context aks-homeease-dev
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd   # one-time, not GitOps-managed
kubectl apply -f argocd/azure/bootstrap/root-app.yaml
```

ArgoCD can't install its own first Application — something has to create
the first one by hand. After that, everything else (both AppProjects,
kube-prometheus-stack, Loki, Alloy, and the 5 service Applications) is
reconciled from this repo automatically.

```bash
kubectl get applications -n argocd
# expect: homeease-root, homeease-project, kube-prometheus-stack, loki, alloy,
#         frontend-dev, admin-frontend-dev, backend-dev, admin-backend-dev, payment-service-dev
```

## Rendering locally before you push

```bash
helm lint charts/backend
helm template backend charts/backend -f charts/backend/values-azure-dev.yaml -n homeease-dev
helm template payment-service charts/payment-service -f charts/payment-service/values-azure-dev.yaml -n homeease-dev
```

Or standalone, into a throwaway namespace, with no live ArgoCD release in
the way:

```bash
helm install backend-demo charts/backend -f charts/backend/values-demo.yaml -n homeease-helm-demo --create-namespace
```

## Environments

Only `dev` exists today, on AKS, and auto-syncs on every merge to `main`
(self-heal + prune on). To add `staging` or `prod`: copy an existing
`charts/<service>/values-azure-dev.yaml` to `values-azure-<env>.yaml` and
adjust its image tag/hostname/replica values, then copy an existing
`argocd/azure/bootstrap/0N-<service>.yaml` to a new file (e.g.
`08-backend-staging.yaml`) pointing at that values file — same mechanism,
no new tooling needed. Once that Application doesn't get a
`syncPolicy.automated` block, a change sits as "OutOfSync" until a human
runs `argocd app sync` — that's the promotion gate for those environments.

## How image tags get here

Nothing in this repo pushes to itself. `app_Homeease`'s CI (Azure
Pipelines, stage 4 "Promote") does, after its Package stage pushes a
newly built image to ACR: it clones this repo, bumps `image.tag` in
`charts/<service>/values-azure-dev.yaml` for every service it actually
rebuilt this run, commits, and pushes straight to `main` — one commit
covering every changed service, since they all share a single
Git-SHA-derived tag. `image.repository` is never touched; only the tag
changes, and only in the one file each service's Application already
reads via `helm.valueFiles`.

That's also why this repo needs no Argo CD change to make promotion
work: every service Application already has `syncPolicy.automated.
selfHeal` and already watches exactly the file CI edits. A pushed tag
bump gets picked up on Argo CD's next poll like any other commit — this
mechanism, not a webhook or a new Application, is what closes the loop
from "image pushed" to "cluster running it".

## Known gaps
 
- **Alertmanager Slack Alerts**: Alertmanager routes to a `null` receiver by default until the `alertmanager-slack` Secret containing the Slack Incoming Webhook URL is created manually in the `monitoring` namespace (see `docs/monitoring-secrets.md`). Real webhook credentials are never committed to Git.
- **Grafana Admin Credentials**: Grafana admin credentials use `grafana.admin.existingSecret` referencing an out-of-band secret (`grafana-admin-credentials`), preventing continuous GitOps drift in ArgoCD (see `docs/monitoring-secrets.md`).
- **AKS Control Plane Monitoring**: On AKS, Kubernetes control plane components (`kube-controller-manager`, `kube-scheduler`, `etcd`, `kube-proxy`) are fully managed by Azure and not accessible from worker nodes. Their respective monitors and `kube-system` service creation are disabled in `platform/kube-prometheus-stack/values.yaml` to prevent invalid scraping targets and namespace permission violations in the `platform` AppProject.

## Keeping these docs honest

`.github/workflows/docs-check.yml` runs
`.github/scripts/check_doc_paths.py` on every push/PR: it scans this file
and `platform/README.md` for backtick/code-block path references into
`charts/`, `argocd/`, `platform/`, `.github/`, and `docs/`, and fails the build if
any of them don't exist on disk. It won't catch every kind of drift, but
it catches the specific failure mode that led to this rewrite — a repo
layout section describing a tree (`apps/...`) that had already been
deleted.

