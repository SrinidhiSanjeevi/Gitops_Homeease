{{/* Selector labels (immutable fields only) */}}
{{- define "frontend.selectorLabels" -}}
app.kubernetes.io/name: frontend
{{- end }}

{{/* Common labels */}}
{{- define "frontend.labels" -}}
app.kubernetes.io/name: frontend
app.kubernetes.io/part-of: homeease
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
