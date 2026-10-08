#!/usr/bin/env bash
# One-time (re-runnable) bootstrap for the EKS cluster: everything that is NOT GitOps-managed.
#   gp3 default StorageClass, Secrets Store CSI driver + AWS provider, ingress-nginx x2, out-of-band
#   monitoring secrets. EKS runs no Argo CD of its own: the Argo CD on AKS (the hub) manages it as
#   cluster `eks-dev`, so the last step registers the cluster there and applies the AWS root Application.
#
# Usage:
#   GRAFANA_ADMIN_PASSWORD='<strong password>' \
#   ALERTMANAGER_SMTP_PASSWORD='<gmail app password>' \
#   scripts/bootstrap-eks.sh
#
#   REGISTER_WITH_HUB=1 additionally runs the hub step. It needs the `argocd` CLI logged in to the AKS
#   Argo CD and a kubeconfig context for AKS (HUB_CONTEXT, default aks-homeease-dev).
#
# Needs AWS credentials able to call eks:DescribeCluster and a cluster access entry (the identity that ran
# `terraform apply` for eks-dev has one automatically). Run by .github/workflows/aws-eks-apply.yml in the
# infrastructure repo (without the hub step), or by hand.
set -euo pipefail

CLUSTER="${CLUSTER:-homeease-eks-dev}"
REGION="${REGION:-ap-south-1}"
HUB_CONTEXT="${HUB_CONTEXT:-aks-homeease-dev}"
cd "$(dirname "$0")/.."

: "${GRAFANA_ADMIN_PASSWORD:?Set GRAFANA_ADMIN_PASSWORD (never commit it)}"
: "${ALERTMANAGER_SMTP_PASSWORD:?Set ALERTMANAGER_SMTP_PASSWORD (never commit it)}"

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
EKS_CONTEXT="$(kubectl config current-context)"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts >/dev/null 2>&1 || true
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "== gp3 default StorageClass (EBS CSI add-on comes from Terraform; Loki and Prometheus PVCs need a default)"
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF
kubectl annotate storageclass gp2 storageclass.kubernetes.io/is-default-class=false --overwrite 2>/dev/null || true

echo "== Secrets Store CSI driver (syncSecret: the charts read secrets as env vars through a synced Secret)"
# tokenRequests: the AWS provider exchanges the pod's projected token (audience sts.amazonaws.com) for its IRSA role.
helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver -n kube-system \
  --set syncSecret.enabled=true --set enableSecretRotation=true \
  --set 'tokenRequests[0].audience=sts.amazonaws.com' --wait

echo "== AWS Secrets Manager provider for the CSI driver (uses each pod's IRSA role)"
# The provider chart bundles its own copy of the CSI driver; the driver installed above is the one we configure.
helm upgrade --install secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws -n kube-system \
  --set secrets-store-csi-driver.install=false --wait

echo "== ingress-nginx, customer (installed by Helm, not Argo CD: every chart's NetworkPolicy allows this namespace)"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  -f platform/aws/ingress-nginx.values.yaml

echo "== ingress-nginx-admin (second controller: own NLB for the admin console)"
helm upgrade --install ingress-nginx-admin ingress-nginx/ingress-nginx -n ingress-nginx \
  -f platform/aws/ingress-nginx-admin.values.yaml

echo "== monitoring secrets (out-of-band, never in Git)"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic grafana-admin-credentials \
  --from-literal=admin-user='admin' \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic alertmanager-smtp \
  --from-literal=password="${ALERTMANAGER_SMTP_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "== ingress load balancers (wait for EXTERNAL-IP / hostname)"
kubectl get svc -n ingress-nginx

if [ "${REGISTER_WITH_HUB:-0}" = "1" ]; then
  echo "== register with the AKS Argo CD (hub) as eks-dev, then apply the AWS root Application there"
  argocd cluster add "$EKS_CONTEXT" --name eks-dev --yes
  kubectl --context "$HUB_CONTEXT" apply -f argocd/aws/bootstrap/root-app.yaml
  kubectl --context "$HUB_CONTEXT" get applications -n argocd | grep -E "NAME|aws"
else
  echo
  echo "Hub step not run. From a machine logged in to the AKS Argo CD:"
  echo "  argocd cluster add $EKS_CONTEXT --name eks-dev"
  echo "  kubectl --context $HUB_CONTEXT apply -f argocd/aws/bootstrap/root-app.yaml"
fi
echo
echo "Next: re-run terraform apply for eks-dev with enable_cloudfront=true (the workflow does this) so CloudFront"
echo "points at these two NLBs."
