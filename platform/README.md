# Platform — monitoring stack

Everything in this folder is deployed by one Argo CD application named `monitoring` (`argocd/azure/bootstrap/05-monitoring.yaml`). It combines several Helm charts with the values files kept here.

| Folder | Component | Purpose |
|---|---|---|
| `kube-prometheus-stack/` | Prometheus, Alertmanager, Grafana | Metrics, alert rules and dashboards |
| `kube-prometheus-stack/dashboards/` | Dashboard ConfigMaps | Business overview, payment service, RED metrics, logs, alerts, DORA |
| `loki/` | Loki | Log storage and search |
| `alloy/` | Grafana Alloy (one pod per node) | Collects container logs and ships them to Loki |
| `dora-exporter/` | Small Python exporter | Turns CI/CD history into the four DORA metrics |

## Notes

- **Business numbers are read from the database**, not counted in memory, so dashboards stay correct across restarts and multiple pods.
- **Alloy** asks for very little CPU on purpose. The two-node dev cluster has its CPU requests almost fully booked by system pods while real usage is low, so a larger request left one Alloy pod unschedulable.
- **Secrets** (Grafana admin password, alert webhook, Azure DevOps token for the DORA exporter) are created once by `scripts/bootstrap-cluster.sh` and are not in Git.
- Dashboards are code: edit the ConfigMap in `kube-prometheus-stack/dashboards` and Argo CD reloads Grafana.

See `dora-exporter/README.md` for the exporter's metrics and its one-time token.
