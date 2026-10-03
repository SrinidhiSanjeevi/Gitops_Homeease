# Monitoring Secrets Management

This document describes how to create out-of-band Kubernetes Secrets for the HomeEase monitoring stack on AKS.

> [!IMPORTANT]
> **NEVER** commit real secret values, credentials, or webhook URLs to Git. The GitOps repository contains only configuration references to these secrets.

---

## 1. Alertmanager e-mail (SMTP) Secret

Alerts are sent by **e-mail only** (Teams is not used). Alertmanager logs in to Gmail as
`adminuserproduct01@gmail.com` (`smtp.gmail.com:587`, STARTTLS) and reads the Google **App Password** from a
file, so it is never in Git.

- **Secret name**: `alertmanager-smtp` (namespace `monitoring`), **key**: `password`
- Mounted by `alertmanagerSpec.secrets` at `/etc/alertmanager/secrets/alertmanager-smtp/password`
  and referenced by `smtp_auth_password_file` in `platform/kube-prometheus-stack/values.yaml`.

Create or rotate it (hidden prompt, spaces removed, nothing printed):

```bash
read -rs -p "App password: " P; echo
kubectl -n monitoring create secret generic alertmanager-smtp --from-literal=password="${P// /}" \
  --dry-run=client -o yaml | kubectl apply -f -; unset P
```
Alertmanager reads the file on config reload; if it was missing at start the pod stays in `Init`.

### Who gets what
| Severity | Recipients |
|---|---|
| warning | DevOps engineer only |
| critical | DevOps engineer immediately |
| critical still firing after 15 min | + team lead (`CriticalUnresolved15m`, label `escalation=lead`) |
| critical still firing after 30 min | + manager (`CriticalUnresolved30m`, label `escalation=manager`) |

Resolved messages (`send_resolved: true`) go to the same recipient(s). Addresses live in the `receivers` block of
`values.yaml`. **Escalation note:** Alertmanager cannot escalate to a different person by itself
(`repeat_interval` only repeats to the same receiver), so the 15/30-minute steps are Prometheus meta-alerts that
fire while *any* critical alert has been continuously firing for that long.

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

> [!IMPORTANT]
> Always verify the password actually landed — a typo'd `--from-literal`
> (e.g. a shell variable that expanded empty) creates the Secret
> successfully with a **blank** `admin-password`, which looks configured
> but locks everyone out. This happened on 2026-09-26. Check with:
> ```bash
> kubectl get secret -n monitoring grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d | wc -c
> ```
> A result of `0` means the password is empty — recreate the Secret.

To initialize `grafana-admin-credentials` with the existing live Grafana password:

```bash
EXISTING_PW=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d)
kubectl create secret generic grafana-admin-credentials \
  --namespace monitoring \
  --from-literal=admin-user='admin' \
  --from-literal=admin-password="$EXISTING_PW"
```

