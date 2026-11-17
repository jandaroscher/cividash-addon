{{/*
Standard labels, shared by every object in this chart.
*/}}
{{- define "cividash.labels" -}}
app.kubernetes.io/part-of: cividash
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
Resolve the cividash_app (php-fpm) image reference.
*/}}
{{- define "cividash.appImage" -}}
{{ .Values.images.app.registry }}/{{ .Values.images.app.repository }}:{{ .Values.images.app.tag }}
{{- end -}}

{{/*
Resolve the cividash_web (nginx) image reference.
*/}}
{{- define "cividash.webImage" -}}
{{ .Values.images.web.registry }}/{{ .Values.images.web.repository }}:{{ .Values.images.web.tag }}
{{- end -}}

{{/*
Resolve APP_KEY: values.app.key wins; else preserve the key already stored in
the cluster's cividash-app-secret (so re-installs don't invalidate encrypted
sessions/cookies); else generate a fresh one. `helm template` has no cluster to
look up, so it always falls into the "generate fresh" branch (documented in
values.yaml and docs/helm-chart.md).
*/}}
{{- define "cividash.appKey" -}}
{{- if .Values.app.key -}}
{{ .Values.app.key }}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace "cividash-app-secret" -}}
{{- if and $existing $existing.data (hasKey $existing.data "APP_KEY") -}}
{{ $existing.data.APP_KEY | b64dec }}
{{- else -}}
{{ printf "base64:%s" (randBytes 32) }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Private platform CA (values.platformCa). PHP's curl and openssl get one bundle
of the image's system CAs plus the platform CA, built by an init container,
so outbound calls to Keycloak and APISIX trust a self-signed platform.
*/}}
{{- define "cividash.platformCa.initContainers" -}}
{{- if .Values.platformCa }}
initContainers:
  - name: ca-bundle
    image: {{ include "cividash.appImage" . }}
    imagePullPolicy: {{ .Values.images.app.pullPolicy }}
    securityContext:
      runAsNonRoot: true
      runAsUser: 82
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
    command: ["sh", "-c", "cat /etc/ssl/certs/ca-certificates.crt /platform-ca/ca.crt > /ca-bundle/ca-bundle.crt"]
    resources:
      requests: { cpu: 10m, memory: 16Mi }
      limits: { cpu: 100m, memory: 32Mi }
    volumeMounts:
      - name: platform-ca
        mountPath: /platform-ca
        readOnly: true
      - name: ca-bundle
        mountPath: /ca-bundle
{{- end }}
{{- end -}}

{{- define "cividash.platformCa.podAnnotations" -}}
{{- if .Values.platformCa }}
annotations:
  # The init container builds the bundle once per pod; roll pods on a CA change.
  checksum/platform-ca: {{ .Values.platformCa | sha256sum }}
{{- end }}
{{- end -}}

{{/*
Pod volumes and container mounts: the platform CA (above) and, with
storage.type=volume, the shared public-media volume.
*/}}
{{- define "cividash.volumeMounts" -}}
{{- if or .Values.platformCa (eq .Values.storage.type "volume") }}
volumeMounts:
{{- if .Values.platformCa }}
  - name: ca-bundle
    mountPath: /ca-bundle
    readOnly: true
  - name: platform-ca
    mountPath: /usr/local/etc/php/conf.d/zz-platform-ca.ini
    subPath: platform-ca.ini
    readOnly: true
{{- end }}
{{- include "cividash.storage.volumeMount" . }}
{{- end }}
{{- end -}}

{{- define "cividash.volumes" -}}
{{- if or .Values.platformCa (eq .Values.storage.type "volume") }}
volumes:
{{- if .Values.platformCa }}
  - name: platform-ca
    configMap:
      name: cividash-platform-ca
  - name: ca-bundle
    emptyDir: {}
{{- end }}
{{- include "cividash.storage.volume" . }}
{{- end }}
{{- end -}}

{{/*
Public media on a volume (storage.type=volume): the app's local "public"
disk writes to storage/app/public, and the web image's public/storage
symlink points there, so nginx serves the files without PHP.
*/}}
{{- define "cividash.storage.volumeMount" -}}
{{- if eq .Values.storage.type "volume" }}
  - name: public-media
    mountPath: /var/www/html/storage/app/public
{{- end }}
{{- end -}}

{{- define "cividash.storage.volume" -}}
{{- if eq .Values.storage.type "volume" }}
  - name: public-media
    persistentVolumeClaim:
      claimName: cividash-public-media
{{- end }}
{{- end -}}
