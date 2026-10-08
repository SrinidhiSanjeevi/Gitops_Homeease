# dora-exporter

In-cluster exporter that turns real CI/CD history into the four DORA metrics for Grafana.
Sources: **Azure DevOps** (every pipeline, branch `main`) and **GitHub Actions** (`aws-ci`, branch `main`).
Deployed on AKS by the `monitoring` Argo CD Application (extra source `platform/dora-exporter`); not deployed on EKS.

| Metric | Meaning |
|---|---|
| `dora_deployment_frequency_per_day` | successful runs on main per day |
| `dora_lead_time_seconds` | median commit -> pipeline finished |
| `dora_change_failure_rate_percent` | failed / all completed runs on main |
| `dora_mttr_seconds` | mean time from a failed run to the next success |

## One-time secret (never in Git)
Azure DevOps needs a read-only token (User settings -> Personal access tokens, scope **Build: Read** only).
The GitHub repo is public, so `github-token` is optional (it only raises the API rate limit).

```bash
kubectl -n monitoring create secret generic dora-exporter \
  --from-literal=ado-pat='<azure-devops-pat>'
kubectl -n monitoring rollout restart deploy/dora-exporter
```
Without the secret the exporter still runs and reports GitHub Actions only.

## Code
The exporter runs from the `exporter.py` key in `configmap.yaml`; `exporter.py` in this folder is the same
code kept as a plain file for reading and local runs. Change both together.
