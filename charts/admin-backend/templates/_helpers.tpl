{{/* Selector labels (immutable fields only) */}}
{{- define "admin-backend.selectorLabels" -}}
app.kubernetes.io/name: admin-backend
{{- end }}

{{/* Common labels */}}
{{- define "admin-backend.labels" -}}
app.kubernetes.io/name: admin-backend
app.kubernetes.io/part-of: homeease
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
