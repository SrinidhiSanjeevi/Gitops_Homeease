{{/*
common.networkpolicy — default-deny, explicit-allow only.

Requires Azure CNI Overlay's NetworkPolicy enforcement to actually be
turned on at cluster creation (Azure NPM or Calico) — CNI Overlay by
itself only controls IP addressing, it does not enforce policy. If
`kubectl describe networkpolicy` shows the object but traffic isn't
actually being blocked, that's the first thing to check, not this
template.

ingress/egress are lists of standard NetworkPolicyIngressRule /
NetworkPolicyEgressRule objects passed through as-is — this template
does not try to build a friendlier DSL on top of the Kubernetes API
shape, so what you write in values.yaml is exactly what you'd write
in a raw NetworkPolicy manifest. Less abstraction, more auditability.
*/}}
{{- define "common.networkpolicy" -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "common.fullname" . }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "common.selectorLabels" . | nindent 6 }}
  policyTypes:
    {{- toYaml .Values.networkPolicy.policyTypes | nindent 4 }}
  {{- if has "Ingress" .Values.networkPolicy.policyTypes }}
  ingress:
    {{- toYaml .Values.networkPolicy.ingress | nindent 4 }}
  {{- end }}
  {{- if has "Egress" .Values.networkPolicy.policyTypes }}
  egress:
    {{- toYaml .Values.networkPolicy.egress | nindent 4 }}
  {{- end }}
{{- end -}}
