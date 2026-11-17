{{- define "stackguard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "stackguard.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "stackguard.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "stackguard.namespace" -}}
{{- .Values.namespace }}
{{- end }}

{{- define "stackguard.labels" -}}
helm.sh/chart: {{ include "stackguard.chart" . }}
{{ include "stackguard.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "stackguard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "stackguard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "stackguard.image" -}}
{{- if .key -}}
{{- $ctx := .ctx -}}
{{- $key := .key -}}
{{- $image := index $ctx.Values.images $key -}}
{{- $registry := $image.registry | default "" -}}
{{- $repository := required "image repository is required" $image.repository -}}
{{- $tag := $image.tag | default "v1.0.0" -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- else -}}
{{- $image := .image -}}
{{- $registry := $image.registry | default "" -}}
{{- $repository := required "image repository is required" $image.repository -}}
{{- $tag := $image.tag | default "v1.0.0" -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "stackguard.publicUrl" -}}
{{- if .url -}}
{{- .url -}}
{{- else -}}
{{- printf "http://localhost:%v" .service.port -}}
{{- end -}}
{{- end }}

{{- define "stackguard.databaseUrl" -}}
{{- if .Values.secrets.databaseUrl -}}
{{- .Values.secrets.databaseUrl -}}
{{- else -}}
{{- printf "postgresql://%s:%s@stackguard-postgres:5432/%s?sslmode=disable" .Values.secrets.postgres.user .Values.secrets.postgres.password .Values.secrets.postgres.database -}}
{{- end -}}
{{- end }}

{{- define "stackguard.redisUrl" -}}
{{- if .Values.secrets.redisUrl -}}
{{- .Values.secrets.redisUrl -}}
{{- else -}}
{{- printf "redis://%s:%s@stackguard-valkey:%v/0" .Values.valkey.auth.user .Values.valkey.auth.password .Values.valkey.service.port -}}
{{- end -}}
{{- end }}
