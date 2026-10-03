#!/usr/bin/env bash
# End-to-end check of the HomeEase Azure flow, layer by layer. Read-only; prints PASS/FAIL/WARN per check
# and never prints secret values. Needs: az (logged in), kubectl (context aks-homeease-dev), curl, python3.
set -uo pipefail

ADO_ORG="${ADO_ORG:-https://dev.azure.com/homeease}"; ADO_PROJECT="${ADO_PROJECT:-HomeEase}"
RG="${RG:-rg-homeease-dev}"; AKS="${AKS:-aks-homeease-dev}"; ACR="${ACR:-acrhomeeasedev01}"; KV="${KV:-kv-homeease-dev-hs02}"
IP="${INGRESS_IP:-52.140.83.144}"; HOSTS="${IP//./-}.nip.io"
NS="${NS:-homeease-dev}"
SERVICES=(backend admin-backend frontend admin-frontend payment-service notification-service)
GITOPS_DIR="${GITOPS_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
FAILS=0; WARNS=0
pass(){ printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail(){ printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS+1)); }
warn(){ printf '  \033[33mWARN\033[0m %s\n' "$*"; WARNS=$((WARNS+1)); }
step(){ printf '\n\033[1m%s\033[0m\n' "$*"; }
PIDS=(); trap 'kill "${PIDS[@]}" 2>/dev/null' EXIT

step "1. Source -> CI (Azure DevOps pipelines on main)"
az pipelines runs list --organization "$ADO_ORG" --project "$ADO_PROJECT" --top 40 -o json 2>/dev/null | python3 -c "
import json,sys
runs=[r for r in json.load(sys.stdin) if r['sourceBranch']=='refs/heads/main' and r['status']=='completed']
seen=set()
for r in sorted(runs,key=lambda r:r['id'],reverse=True):
    n=r['definition']['name']
    if n in seen: continue
    seen.add(n); print(('PASS' if r['result']=='succeeded' else 'FAIL'),n.split('.')[-1],r['buildNumber'],r['result'],r['sourceVersion'][:8])
" | while read -r s name num res sha; do [ "$s" = PASS ] && pass "latest main run of $name: #$num $res ($sha)" || fail "latest main run of $name: #$num $res ($sha)"; done

step "2. Registry (ACR) and GitOps desired state"
for s in "${SERVICES[@]}"; do
  TAG=$(grep -E '^\s+tag:' "$GITOPS_DIR/charts/$s/values-azure-dev.yaml" | head -1 | tr -d ' "' | cut -d: -f2)
  if az acr repository show -n "$ACR" --image "homeease/$s:$TAG" >/dev/null 2>&1; then pass "$s: GitOps tag $TAG exists in ACR"; else fail "$s: GitOps tag '$TAG' NOT in ACR"; fi
done

step "3. Cluster and Argo CD"
READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready"); [ "$READY" -ge 1 ] && pass "$READY node(s) Ready" || fail "no Ready nodes (is the cluster started?)"
BAD=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$2!="Synced"||$3!="Healthy"{print $1"("$2"/"$3")"}')
[ -z "$BAD" ] && pass "all Argo CD applications Synced/Healthy" || fail "Argo CD not healthy: $BAD"
NR=$(kubectl get pods -A --no-headers 2>/dev/null | grep -vE "Running|Completed" | wc -l); [ "$NR" -eq 0 ] && pass "no non-running pods" || fail "$NR non-running pod(s)"
for s in "${SERVICES[@]}"; do
  TAG=$(grep -E '^\s+tag:' "$GITOPS_DIR/charts/$s/values-azure-dev.yaml" | head -1 | tr -d ' "' | cut -d: -f2)
  IMG=$(kubectl get deploy "$s" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  case "$IMG" in *":$TAG") pass "$s runs the GitOps tag $TAG";; *) fail "$s runs '${IMG##*:}' but GitOps says '$TAG'";; esac
done

step "4. Edge: ingress, apps, API version"
for h in home admin-console; do C=$(curl -sk -o /dev/null -m 10 -w '%{http_code}' "https://$h.$HOSTS/"); [ "$C" = 200 ] && pass "$h.$HOSTS -> 200" || fail "$h.$HOSTS -> $C"; done
V=$(curl -sk -m 10 "https://api.$HOSTS/health/live" | python3 -c "import json,sys;print(json.load(sys.stdin).get('version',''))" 2>/dev/null)
BT=$(grep -E '^\s+tag:' "$GITOPS_DIR/charts/backend/values-azure-dev.yaml" | head -1 | tr -d ' "' | cut -d: -f2)
[ "$V" = "$BT" ] && pass "api reports version $V (matches GitOps)" || fail "api reports '$V', GitOps says '$BT'"
C=$(curl -sk -o /dev/null -m 10 -w '%{http_code}' "https://api.$HOSTS/health/ready"); [ "$C" = 200 ] && pass "api /health/ready -> 200 (database connected)" || fail "api ready -> $C"
NIMG=$(curl -sk -m 15 "https://api.$HOSTS/api/services" | python3 -c "
import json,sys
d=json.load(sys.stdin); it=d.get('services') or d.get('data') or d
print(sum(1 for s in it if s.get('imageUrl')),len(it))" 2>/dev/null)
[ -n "$NIMG" ] && [ "${NIMG%% *}" = "${NIMG##* }" ] && [ "${NIMG%% *}" != 0 ] && pass "blob storage images: ${NIMG%% *}/${NIMG##* } services have an image URL" || fail "blob storage images: '${NIMG:-error}' (with imageUrl / total)"

step "5. Secrets (Key Vault -> CSI -> pods)"
for n in mongo-uri notification-mongo-uri email-user email-pass email-from jwt-secret internal-service-token; do
  az keyvault secret show --vault-name "$KV" -n "$n" --query "attributes.enabled" -o tsv 2>/dev/null | grep -q true && pass "KV secret $n present" || fail "KV secret $n missing"
done
KEYS=$(kubectl get secret notification-service-secrets -n "$NS" -o json 2>/dev/null | python3 -c "import json,sys;print(' '.join(sorted(json.load(sys.stdin)['data'])))" 2>/dev/null)
case "$KEYS" in *EMAIL_PASS*MONGO_URI*) pass "notification-service secret synced from Key Vault ($KEYS)";; *) fail "notification-service secret keys: '$KEYS'";; esac
RES=$(kubectl exec -n "$NS" deploy/notification-service -- node -e "
require('nodemailer').createTransport({service:'gmail',auth:{user:process.env.EMAIL_USER,pass:process.env.EMAIL_PASS}}).verify().then(()=>console.log('OK')).catch(e=>console.log('EAUTH '+(e.code||'')))" 2>/dev/null | tail -1)
[ "$RES" = OK ] && pass "SMTP login (Gmail) works" || warn "SMTP login failed ($RES) - check the app password / address; emails will not send"

step "6. Observability (Prometheus, Loki, Grafana, DORA)"
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 19091:9090 >/dev/null 2>&1 & PIDS+=($!)
kubectl port-forward -n monitoring svc/loki 13101:3100 >/dev/null 2>&1 & PIDS+=($!)
sleep 5
DOWN=$(curl -s -G localhost:19091/api/v1/query --data-urlencode 'query=up{job=~"backend|admin-backend|payment-service|notification-service"} == 0' | python3 -c "import json,sys;print(len(json.load(sys.stdin)['data']['result']))" 2>/dev/null)
[ "$DOWN" = 0 ] && pass "Prometheus: all app targets up" || fail "Prometheus: $DOWN app target(s) down (or Prometheus unreachable)"
PAY=$(curl -s -G localhost:19091/api/v1/query --data-urlencode 'query=sum(payment_records_by_status)' | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else '')" 2>/dev/null)
[ -n "$PAY" ] && pass "payment DB gauges present (total payment records: $PAY)" || warn "payment_records_by_status missing - deploy the payment-service change"
LOGS=$(curl -s -G localhost:13101/loki/api/v1/query --data-urlencode 'query=sum(count_over_time({namespace="homeease-dev"}[15m]))' | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];print(int(float(r[0]['value'][1])) if r else 0)" 2>/dev/null)
[ "${LOGS:-0}" -gt 0 ] && pass "Loki: $LOGS app log lines in the last 15 min (Alloy shipping)" || fail "Loki: no recent app logs"
DASH=$(kubectl get cm -n monitoring -l grafana_dashboard=1 --no-headers 2>/dev/null | grep -c homeease); [ "$DASH" -ge 4 ] && pass "$DASH HomeEase dashboards loaded in Grafana" || warn "only $DASH HomeEase dashboards"
ERR=$(kubectl exec -n monitoring deploy/dora-exporter -- python3 -c "import urllib.request;print(urllib.request.urlopen('http://localhost:9102/metrics').read().decode())" 2>/dev/null | grep -E '^dora_exporter_errors' | awk '{s+=$2} END{print s+0}')
[ "${ERR:-1}" = 0 ] && pass "DORA exporter: Azure DevOps and GitHub both reachable" || warn "DORA exporter has fetch errors ($ERR) - check the dora-exporter secret (Azure DevOps PAT)"

step "7. Infrastructure as code (Azure resources managed by Terraform)"
for r in "$AKS:Microsoft.ContainerService/managedClusters" "$ACR:Microsoft.ContainerRegistry/registries" "$KV:Microsoft.KeyVault/vaults"; do
  az resource list -g "$RG" --query "[?name=='${r%%:*}'].tags.managed_by | [0]" -o tsv 2>/dev/null | grep -q terraform && pass "${r%%:*} tagged managed_by=terraform" || warn "${r%%:*} not tagged managed_by=terraform"
done
SA=$(az storage account show -n sthomeeaseimgayhiue -g rg-homeease-data --query id -o tsv 2>/dev/null)
az role assignment list --scope "$SA" --query "[?roleDefinitionName=='Storage Blob Data Contributor'].principalId" -o tsv 2>/dev/null | grep -q "$(az identity show -g "$RG" -n id-homeease-app-dev --query principalId -o tsv 2>/dev/null)" && pass "app identity has blob access on the image storage account" || fail "app identity has NO blob role on the image storage account (apply terraform/persistent/azure-storage)"

printf '\n\033[1mResult: %d failed, %d warning(s)\033[0m\n' "$FAILS" "$WARNS"; [ "$FAILS" -eq 0 ]
