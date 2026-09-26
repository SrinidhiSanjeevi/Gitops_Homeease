# Monitoring Secrets Management

This document describes how to create out-of-band Kubernetes Secrets for the HomeEase monitoring stack on AKS.

> [!IMPORTANT]
> **NEVER** commit real secret values, credentials, or webhook URLs to Git. The GitOps repository contains only configuration references to these secrets.

---

## 1. Alertmanager Microsoft Teams Secret

Alertmanager routes every alert to a Teams receiver (`msteamsv2_configs`) —
`teams-monitoring` by default, plus `teams-infra` and the incidents
L1/L2 escalation routes (see `platform/kube-prometheus-stack/values.yaml`
for the full routing tree). Routing stays broken until this Secret
exists: the mount is mandatory, so a missing Secret leaves the
Alertmanager pod stuck in `Init`. The webhook URLs live only in the
cluster, never in Git.

- **Secret name**: `alertmanager-teams` (namespace `monitoring`)
- **Keys**: `monitoring-url`, `infrastructure-url`, `incidents-url` —
  one Teams Workflow ("when a webhook is received") URL per channel,
  created in Power Automate.

```bash
kubectl -n monitoring create secret generic alertmanager-teams \
  --from-literal=monitoring-url='<MONITORING_TEAMS_WEBHOOK_URL>' \
  --from-literal=infrastructure-url='<INFRASTRUCTURE_TEAMS_WEBHOOK_URL>' \
  --from-literal=incidents-url='<INCIDENTS_TEAMS_WEBHOOK_URL>'
```

This Secret is already referenced by `alertmanagerSpec.secrets` and every
`webhook_url_file` in `platform/kube-prometheus-stack/values.yaml` — once
it exists in the cluster, the next Argo CD sync (or `selfHeal`) picks it
up with no other GitOps change needed.

### Adding email as well (optional, not implemented)
`values.yaml` documents but does not wire up an SMTP path for adding an
"incidents" email alongside Teams: add a "Send an email (V2)" step to
the `#incidents` Teams Workflow in Power Automate after its webhook
trigger (no extra Secret needed), or add a real Alertmanager SMTP
receiver — `alertmanager-smtp` Secret (key `password`), `global.smtp_*`
settings, and `email_configs` on the incidents receivers. Neither is
enabled today.

## 2. Grafana Admin Credentials Secret

Grafana uses `grafana.admin.existingSecret: grafana-admin-credentials` to decouple admin credentials from Helm chart rendering, preventing continuous GitOps drift in ArgoCD and avoiding ArgoCD pruning issues with chart-managed secret names.

### Expected Secret Specification
- **Secret Name**: `grafana-admin-credentials`
- **Namespace**: `monitoring`
- **Data Keys**:
  - `admin-user`: Username (default: `admin`)
  - `admin-password`: Strong password

### Manual Creation Command (Out-of-band)
Create this secret manually in the cluster before deploying or syncing Grafana:

```bash
kubectl create secret generic grafana-admin-credentials \
  --namespace monitoring \
  --from-literal=admin-user='admin' \
  --from-literal=admin-password='<YOUR_SECURE_PASSWORD>'
```

To initialize `grafana-admin-credentials` with the existing live Grafana password:

```bash
EXISTING_PW=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d)
kubectl create secret generic grafana-admin-credentials \
  --namespace monitoring \
  --from-literal=admin-user='admin' \
  --from-literal=admin-password="$EXISTING_PW"
```

