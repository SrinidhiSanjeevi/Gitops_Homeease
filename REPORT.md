# Phase reports — Gitops_Homeease

Per-phase verification: raw command output only, no unverified claims.
Each phase's section is appended by the branch that implements it and
carried forward once merged.

---

## Phase 2 — docs rewrite, docs-check workflow, park `argocd/aws`

Branch: `phase-2/docs-and-park-aws`

### What changed

- Rewrote `README.md` to describe the repo as it actually is today:
  Helm charts under `charts/`, a single live ArgoCD install
  (`argocd/azure/`), and `platform/` values-only components. Removed all
  references to the deleted `apps/` Kustomize tree and the two-cloud
  narrative (no EKS cluster was ever deployed).
- Added `.github/scripts/check_doc_paths.py` + `.github/workflows/
  docs-check.yml`: scans `README.md` and `platform/README.md` for
  backtick/code-block path references into `charts/`, `argocd/`,
  `platform/`, `.github/`, and fails if any don't resolve on disk
  (placeholders like `<service>` or `0N` are treated as wildcards).
- Moved `argocd/aws/` → `argocd/_aws-disabled/` (`git mv`, history
  preserved) and added `argocd/_aws-disabled/README.md` explaining why:
  every file there still points at `apps/*/overlays/aws/dev`, which no
  longer exists, and no EKS cluster was ever deployed.
- Fixed a stale `apps/<service>/overlays/azure/` comment in
  `argocd/azure/projects/homeease-appproject.yaml` (found while building
  the path-check tool — same kind of drift the tool is meant to catch,
  in a non-README file it doesn't scan).
- Added `.gitleaks.toml` (this repo had no gitleaks config at all before
  this phase — see gitleaks results below for why one was needed).

### Checks run — raw output

**docs-check** (`python3 .github/scripts/check_doc_paths.py`):
```
docs-check OK — every checked path reference resolves.
exit=0
```
Sanity-checked the tool actually catches drift before trusting the
"OK": temporarily appended a reference to a known-deleted path
(`` `apps/definitely-deleted/overlays/azure/dev` ``) to README.md and
re-ran it — confirmed it failed with that exact path flagged — before
restoring the real content.

**gitleaks, before `.gitleaks.toml`** (`gitleaks detect --source . --redact -v`):
```
1:47AM INF 23 commits scanned.
1:47AM INF scan completed in 655ms
1:47AM WRN leaks found: 12
```
All 12 findings, by File/RuleID (values redacted by gitleaks itself,
never printed):
```
generic-api-key  charts/backend/values-demo.yaml:26
generic-api-key  charts/admin-backend/values-demo.yaml:13
generic-api-key  charts/payment-service/values-demo.yaml:12
generic-api-key  charts/admin-backend/values-azure-dev.yaml:12
generic-api-key  charts/backend/values-azure-dev.yaml:12
generic-api-key  charts/payment-service/values-azure-dev.yaml:9
generic-api-key  apps/admin-backend/overlays/azure/dev/kustomization.yaml:45       (history only, path deleted)
generic-api-key  apps/admin-backend/overlays/azure/dev/secretproviderclass.yaml:22 (history only, path deleted)
generic-api-key  apps/backend/overlays/azure/dev/kustomization.yaml:48             (history only, path deleted)
generic-api-key  apps/backend/overlays/azure/dev/secretproviderclass.yaml:21       (history only, path deleted)
generic-api-key  apps/payment-service/overlays/azure/dev/secretproviderclass.yaml:17 (history only, path deleted)
generic-api-key  apps/payment-service/overlays/azure/dev/kustomization.yaml:35     (history only, path deleted)
```
Every one of these is a `workloadIdentity.clientId` / `client-id`
annotation value — an Azure AD Application GUID. Confirmed non-secret:
these are public application identifiers; the actual authorization
boundary is the federated-credential subject binding
(`system:serviceaccount:<namespace>:<name>`), configured server-side in
Azure AD, not derivable from the clientId value alone. This is the same
false-positive class already documented and allowlisted in
`app_Homeease/.gitleaks.toml`.

**gitleaks, after `.gitleaks.toml`** (`gitleaks detect --source . --config .gitleaks.toml --redact -v`):
```
1:47AM INF 23 commits scanned.
1:47AM INF scan completed in 169ms
1:47AM INF no leaks found
```

**helm lint + helm template**, all 4 charts × both value files
(`values-azure-dev.yaml`, `values-demo.yaml`):
```
=== helm lint charts/backend ===
1 chart(s) linted, 0 chart(s) failed
=== helm template backend -f values-azure-dev.yaml === exit=0
=== helm template backend -f values-demo.yaml === exit=0
=== helm lint charts/frontend ===
1 chart(s) linted, 0 chart(s) failed
=== helm template frontend -f values-azure-dev.yaml === exit=0
=== helm template frontend -f values-demo.yaml === exit=0
=== helm lint charts/admin-backend ===
1 chart(s) linted, 0 chart(s) failed
=== helm template admin-backend -f values-azure-dev.yaml === exit=0
=== helm template admin-backend -f values-demo.yaml === exit=0
=== helm lint charts/payment-service ===
1 chart(s) linted, 0 chart(s) failed
=== helm template payment-service -f values-azure-dev.yaml === exit=0
=== helm template payment-service -f values-demo.yaml === exit=0
```
(Only informational note across all four: `Chart.yaml: icon is
recommended` — no failures.)

### Not verified

- **`docs-check.yml` has not actually run on GitHub Actions** — it was
  only run locally as the plain Python script. Its behavior on the
  actual `actions/checkout` + `actions/setup-python` runner is unverified
  until the PR is opened and CI executes it.
- **No live-cluster verification** — this phase touches no
  ArgoCD-synced paths (README, a new CI workflow, a moved-but-unwired
  directory), so nothing was expected to affect `aks-homeease-dev`. Not
  independently confirmed against the live cluster.
- **PR was not opened** — `gh` CLI is not installed in this environment
  and no `GITHUB_TOKEN`/`GH_TOKEN` is set, so it can't be created via API
  either. Branch is pushed (see below); PR needs to be opened manually
  or by installing `gh` (`sudo apt-get install gh`, needs an interactive
  password this session doesn't have).

### Push / PR

Not pushed automatically — see chat for the exact command and manual PR
link, per "do not push to main" / no destructive or externally-visible
action without explicit confirmation.
