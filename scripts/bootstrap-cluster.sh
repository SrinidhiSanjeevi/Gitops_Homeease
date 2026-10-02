#!/usr/bin/env bash
# One-time (re-runnable) bootstrap for aks-homeease-dev: everything that is NOT GitOps-managed.
#   Argo CD, ingress-nginx, the two out-of-band monitoring secrets, then the root Application.
#
# Usage:
#   GRAFANA_ADMIN_PASSWORD='<strong password>' \
#   TEAMS_WEBHOOK_URL='<Teams workflow URL>' \   # optional: a placeholder is used if unset
#   scripts/bootstrap-cluster.sh
#
# After it finishes it prints the ingress IP. If it differs from the IP in
# charts/*/values-azure-{dev,staging}.yaml (`*.<ip-with-dashes>.nip.io`), update those hosts and push.
set -euo pipefail

RG="${RG:-rg-homeease-dev}"
CLUSTER="${CLUSTER:-aks-homeease-dev}"
cd "$(dirname "$0")/.."

: "${GRAFANA_ADMIN_PASSWORD:?Set GRAFANA_ADMIN_PASSWORD (never commit it)}"
TEAMS_WEBHOOK_URL="${TEAMS_WEBHOOK_URL:-https://example.invalid/replace-with-real-teams-workflow-url}"

az aks get-credentials -g "$RG" -n "$CLUSTER" --overwrite-existing

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "== Argo CD"
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace

echo "== ingress-nginx (installed by Helm, not Argo CD: every chart's NetworkPolicy allows this namespace name)"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace

echo "== monitoring secrets (out-of-band, never in Git)"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic grafana-admin-credentials \
  --from-literal=admin-user='admin' \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic alertmanager-teams \
  --from-literal=monitoring-url="${TEAMS_WEBHOOK_URL}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "== root Application"
kubectl rollout status deploy/argocd-server -n argocd --timeout=300s
kubectl apply -f argocd/azure/bootstrap/root-app.yaml

echo "== ingress IP (wait for EXTERNAL-IP)"
kubectl get svc -n ingress-nginx ingress-nginx-controller
echo "Hosts in charts/*/values-azure-*.yaml must be <svc>.<IP-with-dashes>.nip.io"
echo "Check: kubectl get applications -n argocd"
