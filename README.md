# gitops_homeease

GitOps source of truth for the HomeEase platform, synced into
`aks-homeease-dev` by ArgoCD. Companion to `app_Homeease` (application
code + CI) and `Infrastruture_Homeease` (Terraform).

## Repo layout

```
bootstrap/          the one Application you kubectl apply by hand — everything downstream is generated from here (app-of-apps). Also holds the multi-source Applications for each platform/ component.
platform/           cluster-wide component VALUES (reference data, not watched directly — see platform/README.md): kube-prometheus-stack, Loki, Alloy (done); ingress-nginx, cert-manager (placeholder)
charts/common/      library chart — Deployment/Service/HPA/PDB/ServiceAccount/SecretProviderClass/NetworkPolicy templates, shared by all 4 services
apps/               one thin chart per service (frontend, backend, admin-backend, payment-service), each declaring charts/common as a dependency
projects/           the `homeease` AppProject — scopes what the 4 service Applications are allowed to touch
applicationsets/    the service × environment matrix generator that produces the actual Application objects
```

## Why a library chart instead of 4 copies of the same Deployment YAML

The four services are structurally identical (Node.js HTTP server,
`/health/live` + `/health/ready` + `/metrics`, one container, Key
Vault-backed secrets) and differ only in **values** — image,
port, resource sizing, and whether extra hardening is switched on.
`charts/common` holds the shape once; each `apps/<service>` chart is
a values file plus a handful of one-line template files that call
into it.

## Why an ApplicationSet instead of hand-written Applications

4 services × 3 environments is 12 near-identical Application objects.
Hand-writing them means every new service or environment is a copy-
paste exercise, and a fix to how Applications are structured has to
be applied 12 times. The ApplicationSet's Matrix generator crosses a
service list with an environment list and feeds the result into ONE
Application template — see `applicationsets/homeease-appset.yaml`
for exactly which fields are templated and why.

## How to bootstrap this against a cluster (once, by a human)

```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd   # one-time, not GitOps-managed
kubectl apply -f bootstrap/root-app.yaml
```

ArgoCD cannot install its own first Application — something has to
create the first one by hand. After `root-app.yaml` is applied,
everything else (AppProject, kube-prometheus-stack, Loki, Alloy, the
ApplicationSet, and every service it generates) is reconciled from
this repo automatically.

```bash
kubectl get applications -n argocd
# expect: homeease-root, homeease-project, homeease-applicationsets,
#         kube-prometheus-stack, loki, alloy,
#         frontend-dev, backend-dev, admin-backend-dev, payment-service-dev
```

## Environments

`dev` auto-syncs on every merge to `main` (self-heal + prune on).
`staging` and `prod` are namespace-level environments in the SAME
cluster — not separate clusters — with `syncPolicy.automated`
deliberately omitted, so a change sits as "OutOfSync" until a human
clicks Sync in the ArgoCD UI (or runs `argocd app sync`). That pause
is the promotion gate; see the ADR log for the reasoning.
