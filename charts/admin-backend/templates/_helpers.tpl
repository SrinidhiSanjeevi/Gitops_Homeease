{{/*
Selector labels — used ONLY in immutable/selector fields. Never add
extraLabels here.
*/}}
{{- define "admin-backend.selectorLabels" -}}
app.kubernetes.io/name: admin-backend
{{- end }}

{{/*
Common labels — metadata.labels and pod-template labels only.
*/}}
{{- define "admin-backend.labels" -}}
app.kubernetes.io/name: admin-backend
app.kubernetes.io/part-of: homeease
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
