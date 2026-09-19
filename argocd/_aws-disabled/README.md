# Parked — AWS (EKS) ArgoCD config

**Not read by any live ArgoCD install.** No EKS cluster was ever
deployed, and every Application here still points at
`apps/<service>/overlays/aws/dev` — a Kustomize tree that no longer
exists in this repo (the 4 services moved to `charts/<service>/`, see
the root [README.md](../../README.md)). Left as-is instead of deleted,
because these were never regenerated against the Helm charts and
shouldn't look live in the meantime.

The leading underscore keeps this directory out of `argocd/*/bootstrap`
directory-recurse scans and out of the docs-check path validation
(`.github/workflows/docs-check.yml` only checks paths referenced from
current docs, and nothing in this file is a real target of any AppProject
reference).

## To re-enable AWS instead of deleting this

1. Build `charts/<service>/values-aws-dev.yaml` for each of the 4
   services (mirror `values-azure-dev.yaml`, swapping ACR → ECR image
   repos, the workload-identity mechanism to IRSA, and hostnames).
2. Update each `bootstrap/0N-<service>.yaml` here to `path:
   charts/<service>` with `helm.valueFiles: [values-aws-dev.yaml]`,
   the same migration already done for `argocd/azure/bootstrap/`.
3. Move this directory back to `argocd/aws/` (`git mv
   argocd/_aws-disabled argocd/aws`) and wire it into the root README's
   repo-layout section.
4. Provision the EKS cluster + its own ArgoCD (see the commented
   bootstrap steps in `bootstrap/root-app.yaml`) and `kubectl apply -f
   argocd/aws/bootstrap/root-app.yaml` on it, same one-time manual step
   as the Azure side.
