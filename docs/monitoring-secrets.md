# Monitoring Secrets Management

This document describes how to create out-of-band Kubernetes Secrets for the HomeEase monitoring stack on AKS.

> [!IMPORTANT]
> **NEVER** commit real secret values, credentials, or webhook URLs to Git. The GitOps repository contains only configuration references to these secrets.

---

## 1. Alertmanager email (SMTP) Secret

Alertmanager routes alerts to a `null` receiver until email is configured. The SMTP app password lives only in the cluster, never in Git.

- **Secret name**: `alertmanager-smtp` (namespace `monitoring`)
- **Key**: `password`

Create it with a hidden prompt, so nothing lands in shell history:

```bash
read -rs SMTP_PW
kubectl -n monitoring create secret generic alertmanager-smtp --from-literal=password="$SMTP_PW"
unset SMTP_PW
```

### Enabling email alerts in GitOps
Only after the Secret exists. The Secret mount is mandatory, so if it is missing Alertmanager sticks in `Init`.
1. In `platform/kube-prometheus-stack/values.yaml`, add `alertmanager-smtp` to `alertmanagerSpec.secrets`.
2. In `alertmanager.config`, set the SMTP `global` settings (smarthost, from, username, and `smtp_auth_password_file: /etc/alertmanager/secrets/alertmanager-smtp/password`), add an `email` receiver with `email_configs`, and point `route.receiver` at it.
3. Commit, let Argo CD sync, then check the Alertmanager pod and its logs.

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

