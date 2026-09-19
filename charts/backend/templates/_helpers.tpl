{{/*
Selector labels — used ONLY in immutable/selector fields:
Deployment.spec.selector.matchLabels, Service.spec.selector,
NetworkPolicy.spec.podSelector.matchLabels, ServiceMonitor.spec.selector,
HPA.spec.scaleTargetRef. Never add extraLabels here.
*/}}
{{- define "backend.selectorLabels" -}}
app.kubernetes.io/name: backend
{{- end }}

{{/*
Common labels — metadata.labels and pod-template labels only.
*/}}
{{- define "backend.labels" -}}
app.kubernetes.io/name: backend
app.kubernetes.io/part-of: homeease
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
