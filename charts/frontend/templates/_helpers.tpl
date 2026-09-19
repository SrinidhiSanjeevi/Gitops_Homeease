{{/*
Selector labels — used ONLY in immutable/selector fields:
Deployment.spec.selector.matchLabels, Service.spec.selector,
NetworkPolicy.spec.podSelector.matchLabels, HPA.spec.scaleTargetRef.
Never add extraLabels or Helm chart bookkeeping labels here — a selector
mismatch forces resource replacement or silently breaks traffic/policy.
*/}}
{{- define "frontend.selectorLabels" -}}
app.kubernetes.io/name: frontend
{{- end }}

{{/*
Common labels — metadata.labels and pod-template labels only. Includes
the selector label plus part-of and any environment-specific extras
(homeease.io/environment, homeease.io/cloud) from values, matching what
the Kustomize `labels:` transformer with includeSelectors: false already
does today.
*/}}
{{- define "frontend.labels" -}}
app.kubernetes.io/name: frontend
app.kubernetes.io/part-of: homeease
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
