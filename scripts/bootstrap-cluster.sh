#!/usr/bin/env bash
# One-time (re-runnable) bootstrap for aks-homeease-dev: everything that is NOT GitOps-managed.
#   Argo CD, ingress-nginx x2, cert-manager, the two out-of-band monitoring secrets, then the root
#   Application. This Argo CD is also the hub for EKS: scripts/bootstrap-eks.sh registers that cluster here.
#
# Usage:
#   GRAFANA_ADMIN_PASSWORD='<strong password>' \
#   ALERTMANAGER_SMTP_PASSWORD='<gmail app password>' \
#   scripts/bootstrap-cluster.sh
#
# After it finishes it prints the ingress services. The frontends use the Azure DNS labels homeease-app /
# homeease-admin (*.centralindia.cloudapp.azure.com). The API hosts in charts/{backend,admin-backend}/
# values-azure-dev.yaml are `*.<ingress-ip-with-dashes>.nip.io`: update them if the ingress IP changed.
set -euo pipefail

RG="${RG:-rg-homeease-dev}"
CLUSTER="${CLUSTER:-aks-homeease-dev}"
cd "$(dirname "$0")/.."

: "${GRAFANA_ADMIN_PASSWORD:?Set GRAFANA_ADMIN_PASSWORD (never commit it)}"
: "${ALERTMANAGER_SMTP_PASSWORD:?Set ALERTMANAGER_SMTP_PASSWORD (never commit it)}"

az aks get-credentials -g "$RG" -n "$CLUSTER" --overwrite-existing

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "== Argo CD"
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace

echo "== ingress-nginx (installed by Helm, not Argo CD: every chart's NetworkPolicy allows this namespace name)"
# The Azure LB health probe must hit /healthz: the default probe path "/" returns 404 on a controller
# with no catch-all host, which marks port 80 down (HTTP-01 certificate challenges then time out).
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set-string 'controller.service.annotations.service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path=/healthz'

echo "== ingress-nginx-admin (second controller: own public IP + Azure DNS label for the admin console)"
helm upgrade --install ingress-nginx-admin ingress-nginx/ingress-nginx -n ingress-nginx -f platform/ingress-nginx-admin/values.yaml

echo "== cert-manager (HTTPS certificates from Let's Encrypt)"
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true --wait
kubectl apply -f platform/cert-manager/clusterissuers.yaml

echo "== monitoring secrets (out-of-band, never in Git)"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic grafana-admin-credentials \
  --from-literal=admin-user='admin' \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic alertmanager-smtp \
  --from-literal=password="${ALERTMANAGER_SMTP_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "== root Application"
kubectl rollout status deploy/argocd-server -n argocd --timeout=300s
kubectl apply -f argocd/azure/bootstrap/root-app.yaml

echo "== ingress IP (wait for EXTERNAL-IP)"
kubectl get svc -n ingress-nginx
echo "Check: kubectl get applications -n argocd"
