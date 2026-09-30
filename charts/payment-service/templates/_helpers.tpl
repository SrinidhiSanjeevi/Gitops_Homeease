{{/* Selector labels (immutable fields only) */}}
{{- define "payment-service.selectorLabels" -}}
app.kubernetes.io/name: payment-service
{{- end }}

{{/* Common labels */}}
{{- define "payment-service.labels" -}}
app.kubernetes.io/name: payment-service
app.kubernetes.io/part-of: homeease
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
