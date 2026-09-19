{{/*
Selector labels — used ONLY in immutable/selector fields. Never add
extraLabels here.
*/}}
{{- define "payment-service.selectorLabels" -}}
app.kubernetes.io/name: payment-service
{{- end }}

{{/*
Common labels — metadata.labels and pod-template labels only.
*/}}
{{- define "payment-service.labels" -}}
app.kubernetes.io/name: payment-service
app.kubernetes.io/part-of: homeease
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
