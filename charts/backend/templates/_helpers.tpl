{{/* Selector labels (immutable fields only) */}}
{{- define "backend.selectorLabels" -}}
app.kubernetes.io/name: backend
{{- end }}

{{/* Common labels */}}
{{- define "backend.labels" -}}
app.kubernetes.io/name: backend
app.kubernetes.io/part-of: homeease
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
