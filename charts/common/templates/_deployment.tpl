{{/*
common.deployment — the one Deployment shape all four HomeEase
services share. Call it from apps/<service>/templates/deployment.yaml
as:
    {{ include "common.deployment" . }}
*/}}
{{- define "common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "common.fullname" . }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "common.selectorLabels" . | nindent 8 }}
        {{- if .Values.workloadIdentity.enabled }}
        {{/* Required on the POD itself, not just the ServiceAccount —
        the workload identity mutating webhook checks this label here
        before it will inject the federated-token projected volume. */}}
        azure.workload.identity/use: "true"
        {{- end }}
        {{- with .Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      serviceAccountName: {{ include "common.serviceAccountName" . }}
      {{- if .Values.priorityClassName }}
      priorityClassName: {{ .Values.priorityClassName }}
      {{- end }}
      terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds | default 30 }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: {{ include "common.name" . }}
          image: "{{ .Values.image.repository }}:{{ required "image.tag is required — never blank, never :latest" .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
              protocol: TCP
          {{- with .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.startupProbe }}
          startupProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          {{- with .Values.env }}
          env:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.envFrom }}
          envFrom:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          volumeMounts:
            {{- with .Values.volumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
            {{- if .Values.secretProviderClass.enabled }}
            - name: secrets-store
              mountPath: "/mnt/secrets-store"
              readOnly: true
            {{- end }}
            {{- if .Values.securityContext.readOnlyRootFilesystem }}
            {{/*
            readOnlyRootFilesystem is on by default. Node.js, npm and
            several libraries (multer temp uploads, log rotation
            scratch files) write to /tmp unconditionally — without
            this, every service would hit read-only-filesystem errors
            the first time something touched /tmp, not at chart-review
            time. One emptyDir, standardised here instead of
            re-discovered per service.
            */}}
            - name: tmp
              mountPath: /tmp
            {{- end }}
          {{- with .Values.extraVolumeMounts }}
            {{- toYaml . | nindent 12 }}
          {{- end }}
      volumes:
        {{- with .Values.volumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- if .Values.secretProviderClass.enabled }}
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: {{ include "common.fullname" . }}
        {{- end }}
        {{- if .Values.securityContext.readOnlyRootFilesystem }}
        - name: tmp
          emptyDir: {}
        {{- end }}
        {{- with .Values.extraVolumes }}
          {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end -}}
