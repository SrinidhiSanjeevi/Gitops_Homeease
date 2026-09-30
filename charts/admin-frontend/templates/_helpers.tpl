{{/* Selector labels (immutable fields only) */}}
{{- define "admin-frontend.selectorLabels" -}}
app.kubernetes.io/name: admin-frontend
{{- end }}

{{/* Common labels */}}
{{- define "admin-frontend.labels" -}}
app.kubernetes.io/name: admin-frontend
app.kubernetes.io/part-of: homeease
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
