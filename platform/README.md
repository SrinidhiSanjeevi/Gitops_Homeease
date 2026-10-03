# platform/

Cluster-wide components. Each subdirectory holds a `values.yaml` —
**reference data only**, never watched directly by Argo CD as a
directory of raw manifests (a values file has no `apiVersion`/`kind`,
so a directory-recurse Application would fail trying to parse it as
one). All three are deployed by ONE multi-source Application,
`argocd/azure/bootstrap/05-monitoring.yaml`: each upstream Helm chart
(pinned version) is a source whose `helm.valueFiles` points at
`$values/platform/<component>/values.yaml`, plus a source for
`platform/kube-prometheus-stack/dashboards` (Grafana dashboard
ConfigMaps and the `homeease-alerts` PrometheusRule).

It runs in the `platform` AppProject
(`argocd/azure/projects/platform-appproject.yaml`), not `homeease`:
platform components need CRDs, ClusterRoles and webhooks, and the
`homeease` project deliberately allows no cluster-scoped kind except
`Namespace`.

| Folder | Status | What it is |
|---|---|---|
| `kube-prometheus-stack/` | **done** | Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics. `serviceMonitorSelectorNilUsesHelmValues: false` etc. set so it watches ServiceMonitors from ANY Helm release, in any namespace — without this, the four app charts' future ServiceMonitors would silently never be scraped. |
| `loki/` | **done** | SingleBinary mode, filesystem-backed (not object-storage — see the values file for why that's a documented limitation, not an oversight). |
| `alloy/` | **done** | Ships every pod's stdout/stderr to Loki. Not Promtail — Promtail reached end-of-life 2026-03-02. |
| `dora-exporter/` | **done** | In-cluster exporter: reads Azure DevOps + GitHub Actions history and serves the four DORA metrics (`dora_*`) for the **HomeEase - DORA Metrics** dashboard. Needs one out-of-band secret (see its README). Deployed as an extra source of the `monitoring` Application. |
| `ingress-nginx/` | placeholder | **Installed manually with Helm, not by Argo CD** (namespace `ingress-nginx`; every chart's NetworkPolicy allows traffic from that namespace name). Hosts are `<svc>.<ingress-ip-with-dashes>.nip.io`. |
| `cert-manager/` | placeholder | Not installed. The Ingresses carry a `cert-manager.io/cluster-issuer` annotation that stays inert until it is; HTTPS currently serves ingress-nginx's self-signed default certificate. |

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

## Observability — what is actually wired

- **Scraping.** `backend`, `admin-backend` and `payment-service` each ship a
  ServiceMonitor (`charts/<service>/templates/servicemonitor.yaml`,
  `port: http`, `path: /metrics`, 15s). The Prometheus `job` label is the
  Service name. `/metrics` is not routed by any Ingress (only `/api` and
  `/health` are), so it is reachable only inside the cluster.
- **Business gauges** (`serviceexpress_total_*`, `serviceexpress_bookings_by_status`,
  `serviceexpress_active_bookings`, …) are MongoDB counts refreshed every 30s by
  the backend's metrics collector, which runs in every backend replica
  (disable with `METRICS_COLLECTOR_ENABLED=false`). Every replica exports the
  same values, so dashboards aggregate them with `max()`, never `sum()`.
- **Event counters** (`serviceexpress_bookings_*_total`, `payment_*_total`) are
  per-pod and reset on restart; dashboards use `increase()` over the selected
  time range, wrapped in `round()` for whole-number counts, or `rate()` for
  per-second throughput.
- **Dashboards:** `platform/kube-prometheus-stack/dashboards/homeease-*.yaml`
  (loaded by the Grafana sidecar via the `grafana_dashboard: "1"` label).
- **Alerts:** `platform/kube-prometheus-stack/dashboards/homeease-alerts.yaml`
  plus the chart's default rules. **Alertmanager routes everything to the
  `null` receiver** — alerts fire and are visible in Prometheus/Alertmanager,
  but nothing is sent until a receiver is configured
  (see `docs/monitoring-secrets.md`).
