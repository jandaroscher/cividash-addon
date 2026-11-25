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
Init containers of the PHP pods: writable-dirs (below) and, with a private
platform CA (values.platformCa), ca-bundle. PHP's curl and openssl get one
bundle of the image's system CAs plus the platform CA, so outbound calls to
Keycloak and APISIX trust a self-signed platform.
*/}}
{{- define "cividash.initContainers" -}}
initContainers:
{{- include "cividash.writable.initContainer" . }}
{{- if .Values.platformCa }}
  - name: ca-bundle
    image: {{ include "cividash.appImage" . }}
    imagePullPolicy: {{ .Values.images.app.pullPolicy }}
    securityContext:
      runAsNonRoot: true
      runAsUser: 82
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
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
Pod volumes and container mounts of the PHP pods: the writable paths (below),
the platform CA (above) and, with storage.type=volume, the shared public-media
volume.
*/}}
{{- define "cividash.volumeMounts" -}}
volumeMounts:
{{- include "cividash.writable.volumeMounts" . }}
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
{{- end -}}

{{- define "cividash.volumes" -}}
volumes:
{{- include "cividash.writable.volumes" . }}
{{- if .Values.platformCa }}
  - name: platform-ca
    configMap:
      name: cividash-platform-ca
  - name: ca-bundle
    emptyDir: {}
{{- end }}
{{- include "cividash.storage.volume" . }}
{{- end -}}

{{/*
The PHP containers run with a read-only root filesystem. Laravel writes its
caches (config, routes, views, Filament components; warmed by the image's
entrypoint at every start), sessions and uploads under storage/ and
bootstrap/cache, PHP its temp files to /tmp: each gets a pod-local emptyDir,
which is what the container's own filesystem was before. Laravel refuses to
boot without the storage/framework directories, so the writable-dirs init
container first copies the image's storage/ and bootstrap/cache/ into them.
*/}}
{{- define "cividash.writable.initContainer" }}
  - name: writable-dirs
    image: {{ include "cividash.appImage" . }}
    imagePullPolicy: {{ .Values.images.app.pullPolicy }}
    securityContext:
      runAsNonRoot: true
      runAsUser: 82
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
    command: ["sh", "-c", "cp -R /var/www/html/storage/. /writable/storage/ && cp -R /var/www/html/bootstrap/cache/. /writable/bootstrap-cache/"]
    resources:
      requests: { cpu: 10m, memory: 16Mi }
      limits: { cpu: 100m, memory: 32Mi }
    volumeMounts:
      - name: storage
        mountPath: /writable/storage
      - name: bootstrap-cache
        mountPath: /writable/bootstrap-cache
{{- end -}}

{{- define "cividash.writable.volumeMounts" }}
  - name: tmp
    mountPath: /tmp
  - name: storage
    mountPath: /var/www/html/storage
  - name: bootstrap-cache
    mountPath: /var/www/html/bootstrap/cache
{{- end -}}

{{- define "cividash.writable.volumes" }}
  - name: tmp
    emptyDir: {}
  - name: storage
    emptyDir: {}
  - name: bootstrap-cache
    emptyDir: {}
{{- end -}}

{{/*
Environment of the PHP containers besides the envFrom Secrets. HOME points at
the writable /tmp, because the image's home directory is on the read-only root
and artisan tinker (used by cividash-seed) fails if it cannot write its config
there. With app.s3.existingSecret, the S3 credentials come from that
operator-created Secret instead of values rendered into cividash-app-secret.
*/}}
{{- define "cividash.env" -}}
env:
  - name: HOME
    value: /tmp
{{- if and (eq .Values.storage.type "s3") .Values.app.s3.existingSecret }}
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: {{ .Values.app.s3.existingSecret }}
        key: AWS_ACCESS_KEY_ID
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: {{ .Values.app.s3.existingSecret }}
        key: AWS_SECRET_ACCESS_KEY
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
