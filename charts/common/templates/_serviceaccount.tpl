{{/*
common.serviceaccount — one per service, not a shared default SA.

Azure Workload Identity federates on (namespace, service account
name) — see terraform/azure/modules/workload-identity. A shared SA
across services means every service inherits whatever Key Vault
access the SA carries, which is the opposite of the "payment-service
should have a smaller blast radius" principle. The
azure.workload.identity/client-id label is set per service in that
service's values file, pointing at its own federated identity (or
left unset for services that don't need Key Vault access directly).
*/}}
{{- define "common.serviceaccount" -}}
{{- if .Values.serviceAccount.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "common.serviceAccountName" . }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
    {{- if .Values.workloadIdentity.enabled }}
    azure.workload.identity/use: "true"
    {{- end }}
    {{- with .Values.serviceAccount.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- if or .Values.workloadIdentity.enabled .Values.serviceAccount.annotations }}
  annotations:
    {{- if .Values.workloadIdentity.enabled }}
    azure.workload.identity/client-id: {{ required "workloadIdentity.clientId is required when workloadIdentity.enabled is true" .Values.workloadIdentity.clientId | quote }}
    {{- end }}
    {{- with .Values.serviceAccount.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end -}}
