{{/* Selector labels (immutable fields only) */}}
{{- define "notification-service.selectorLabels" -}}
app.kubernetes.io/name: notification-service
{{- end }}

{{/* Common labels */}}
{{- define "notification-service.labels" -}}
app.kubernetes.io/name: notification-service
app.kubernetes.io/part-of: homeease
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
