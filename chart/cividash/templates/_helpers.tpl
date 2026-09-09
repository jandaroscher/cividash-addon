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
values.yaml and the README "Helm chart" section).
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
