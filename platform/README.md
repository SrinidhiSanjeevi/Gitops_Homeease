# platform/

Cluster-wide components. Each subdirectory holds a `values.yaml` —
**reference data only**, never watched directly by Argo CD as a
directory of raw manifests (a values file has no `apiVersion`/`kind`,
so a directory-recurse Application would fail trying to parse it as
one). Each component's actual `Application` resource lives in
`bootstrap/` instead, as a **multi-source** Application: one source
is the real, versioned Helm chart from its upstream repo; the second
source is this git repo, referenced only so the first source's
`helm.valueFiles` can point at `$values/platform/<component>/values.yaml`.
See any of `bootstrap/03-kube-prometheus-stack.yaml`,
`04-loki.yaml`, `05-alloy.yaml` for the exact pattern.

All three are in the `default` AppProject, not `homeease` — platform
components need ClusterRoles/CRDs/webhooks, and `homeease`'s whole
point (see `projects/homeease-appproject.yaml`) is to deny cluster-
scoped resources to the four app Applications. Mixing the two would
mean widening `homeease` just to let platform components through.

| Folder | Status | What it is |
|---|---|---|
| `kube-prometheus-stack/` | **done** | Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics. `serviceMonitorSelectorNilUsesHelmValues: false` etc. set so it watches ServiceMonitors from ANY Helm release, in any namespace — without this, the four app charts' future ServiceMonitors would silently never be scraped. |
| `loki/` | **done** | SingleBinary mode, filesystem-backed (not object-storage — see the values file for why that's a documented limitation, not an oversight). |
| `alloy/` | **done** | Ships every pod's stdout/stderr to Loki. Not Promtail — Promtail reached end-of-life 2026-03-02. |
| `ingress-nginx/` | placeholder | Not yet needed; services are ClusterIP-only until something outside the cluster needs to reach them. Pairs with the free-DNS task when it happens. |
| `cert-manager/` | placeholder | TLS certs for ingress, once ingress exists. |

Deliberately NOT here: the Secrets Store CSI driver + Azure Key Vault
provider. Those ship as the AKS-managed `key_vault_secrets_provider`
add-on (already enabled in `terraform/azure/modules/aks/main.tf`) —
installing them again via Helm here would fight the AKS-managed
version.

## Verifying this without a live cluster

Every values file here was rendered against the REAL chart before
being committed, not just checked for YAML syntax:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm template kps prometheus-community/kube-prometheus-stack --version 90.0.0 -f kube-prometheus-stack/values.yaml -n monitoring
helm template loki grafana/loki --version 7.3.0 -f loki/values.yaml -n monitoring
helm template alloy grafana/alloy --version 1.12.1 -f alloy/values.yaml -n monitoring
```

Alloy's River config (embedded in `alloy/values.yaml` as
`alloy.configMap.content`) was additionally validated against the
real `alloy` binary:

```bash
docker run --rm -v ./config.river:/etc/alloy/config.river:ro \
  grafana/alloy:v1.19.2 validate /etc/alloy/config.river
```

None of this proves it works end-to-end on a real cluster — no
cluster was reachable while building this — but it does mean every
value is schema-valid against the actual chart version pinned, not
guessed.
