#!/usr/bin/env bash
# One-time (re-runnable) bootstrap for the EKS cluster: everything that is NOT GitOps-managed.
#   Secrets Store CSI driver + AWS provider, ingress-nginx x2, Argo CD, out-of-band monitoring secrets,
#   then the root Application. Mirrors scripts/bootstrap-cluster.sh (AKS).
#
# Usage:
#   GRAFANA_ADMIN_PASSWORD='<strong password>' \
#   ALERTMANAGER_SMTP_PASSWORD='<gmail app password>' \
#   scripts/bootstrap-eks.sh
#
# Needs AWS credentials able to call eks:DescribeCluster and a cluster access entry (the identity that ran
# `terraform apply` for eks-dev has one automatically). Run by .github/workflows/aws-eks-apply.yml in the
# infrastructure repo, or by hand.
set -euo pipefail

CLUSTER="${CLUSTER:-homeease-eks-dev}"
REGION="${REGION:-ap-south-1}"
cd "$(dirname "$0")/.."

: "${GRAFANA_ADMIN_PASSWORD:?Set GRAFANA_ADMIN_PASSWORD (never commit it)}"
: "${ALERTMANAGER_SMTP_PASSWORD:?Set ALERTMANAGER_SMTP_PASSWORD (never commit it)}"

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts >/dev/null 2>&1 || true
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "== Secrets Store CSI driver (syncSecret: the charts read secrets as env vars through a synced Secret)"
helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver -n kube-system \
  --set syncSecret.enabled=true --set enableSecretRotation=true --wait

echo "== AWS Secrets Manager provider for the CSI driver (uses each pod's IRSA role)"
helm upgrade --install secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws -n kube-system --wait

echo "== ingress-nginx, customer (installed by Helm, not Argo CD: every chart's NetworkPolicy allows this namespace)"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  -f platform/aws/ingress-nginx.values.yaml

echo "== ingress-nginx-admin (second controller: own NLB for the admin console)"
helm upgrade --install ingress-nginx-admin ingress-nginx/ingress-nginx -n ingress-nginx \
  -f platform/aws/ingress-nginx-admin.values.yaml

echo "== Argo CD"
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace

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
kubectl apply -f argocd/aws/bootstrap/root-app.yaml

echo "== ingress load balancers (wait for EXTERNAL-IP / hostname)"
kubectl get svc -n ingress-nginx
echo
echo "Next: re-run terraform apply for eks-dev with enable_cloudfront=true (the workflow does this) so CloudFront"
echo "points at these two NLBs. Check: kubectl get applications -n argocd"
