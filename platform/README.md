# Platform — monitoring and cluster add-ons

The monitoring stack is deployed by Argo CD as one multi-source application per cluster:

- `monitoring` on AKS (`argocd/azure/bootstrap/05-monitoring.yaml`), including the DORA exporter.
- `monitoring-aws` on EKS (`argocd/aws/bootstrap/05-monitoring.yaml`), the same stack without the DORA exporter.

Both use the Helm charts listed below with the values files kept here.

| Folder | Component | Purpose |
|---|---|---|
| `kube-prometheus-stack/` | Prometheus, Alertmanager, Grafana | Metrics, alert rules, email alerts and dashboards |
| `kube-prometheus-stack/dashboards/` | Dashboard ConfigMaps | Business overview, payment service, RED metrics, logs, alerts, DORA |
| `loki/` | Loki | Log storage and search |
| `alloy/` | Grafana Alloy (one pod per node) | Collects container logs and ships them to Loki |
| `dora-exporter/` | Small Python exporter (AKS only) | Turns CI/CD history into the four DORA metrics |

These are installed with Helm by the bootstrap scripts, not by Argo CD:

| Folder | Used by | Purpose |
|---|---|---|
| `ingress-nginx-admin/` | `scripts/bootstrap-cluster.sh` | Second ingress controller on AKS with its own public IP for the admin console |
| `cert-manager/` | `scripts/bootstrap-cluster.sh` | Let's Encrypt ClusterIssuers for HTTPS on AKS |
| `aws/` | `scripts/bootstrap-eks.sh` | The two ingress-nginx controllers on EKS, each behind its own NLB (CloudFront terminates HTTPS) |

## Notes

- **Business numbers are read from the database**, not counted in memory, so dashboards stay correct across restarts and multiple pods.
- **Alloy** asks for very little CPU on purpose. The two-node dev cluster has its CPU requests almost fully booked by system pods while real usage is low, so a larger request left one Alloy pod unschedulable.
- **Secrets** are not in Git. The bootstrap scripts create `grafana-admin-credentials` and `alertmanager-smtp` (the Gmail app password Alertmanager sends with). The DORA exporter's Azure DevOps token is created by hand; see `dora-exporter/README.md`.
- **Storage:** Prometheus, Alertmanager and Loki use PVCs on the default StorageClass (managed disks on AKS, `gp3` on EKS, created by `bootstrap-eks.sh`).
- Dashboards are code: edit the ConfigMap in `kube-prometheus-stack/dashboards` and Argo CD reloads Grafana.
