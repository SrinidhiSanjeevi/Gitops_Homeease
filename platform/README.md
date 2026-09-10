# platform/

Cluster-wide components, synced by the `homeease-platform` Application
(`bootstrap/01-platform.yaml`) into the `default` AppProject — not the
`homeease` project, which deliberately denies cluster-scoped
resources. Platform components need ClusterRoles/CRDs/webhooks;
application services should never be able to create those, so they
live in a separate project on purpose.

| Folder | Status | What goes here |
|---|---|---|
| `ingress-nginx/` | placeholder | NGINX ingress controller — not yet needed; services are ClusterIP-only until something outside the cluster needs to reach them |
| `cert-manager/` | placeholder | TLS certs for ingress, once ingress exists |
| `kube-prometheus-stack/` | **next task** | Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics |
| `loki/` | **next task** | Log aggregation, paired with kube-prometheus-stack's Grafana |

Deliberately NOT here: the Secrets Store CSI driver + Azure Key Vault
provider. Those ship as the AKS-managed `key_vault_secrets_provider`
add-on (already enabled in `terraform/azure/modules/aks/main.tf`) —
installing them again via Helm here would fight the AKS-managed
version. `common.secretproviderclass` in `charts/common` assumes this
add-on is already present.
