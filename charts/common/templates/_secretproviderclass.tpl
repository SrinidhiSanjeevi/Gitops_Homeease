{{/*
common.secretproviderclass — Azure Key Vault provider for the
Secrets Store CSI driver (the driver + azure provider ship as the
AKS-managed `key_vault_secrets_provider` addon — already enabled in
terraform/azure/modules/aks — so nothing extra needs installing in
platform/ for this to work).

Requires workloadIdentity.enabled so the driver can authenticate to
Key Vault as this service's own identity, not a shared one — see
common.serviceaccount for where clientID actually gets wired in.
*/}}
{{- define "common.secretproviderclass" -}}
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: {{ include "common.fullname" . }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  provider: azure
  parameters:
    clientID: {{ required "workloadIdentity.clientId is required when secretProviderClass.enabled is true" .Values.workloadIdentity.clientId | quote }}
    keyvaultName: {{ required "secretProviderClass.keyvaultName is required" .Values.secretProviderClass.keyvaultName | quote }}
    tenantId: {{ required "secretProviderClass.tenantId is required" .Values.secretProviderClass.tenantId | quote }}
    objects: |
      array:
        {{- range .Values.secretProviderClass.objects }}
        - |
          objectName: {{ .objectName }}
          objectType: {{ .objectType | default "secret" }}
          {{- if .objectVersion }}
          objectVersion: {{ .objectVersion }}
          {{- end }}
        {{- end }}
  {{- with .Values.secretProviderClass.secretObjects }}
  secretObjects:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
