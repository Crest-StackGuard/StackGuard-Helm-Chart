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
{{- default .Release.Namespace .Values.namespace }}
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

{{/*
Resolve a container image reference for component key .key.
Azure Marketplace rewrites global.azure.images.<key>, so it wins when present.
*/}}
{{- define "stackguard.image" -}}
{{- $ctx := .ctx -}}
{{- $key := .key -}}
{{- $azure := dig "azure" "images" $key nil $ctx.Values.global -}}
{{- if and $azure (or $azure.image $azure.repository) -}}
{{- $registry := $azure.registry | default "" -}}
{{- $repository := $azure.image | default $azure.repository -}}
{{- $ref := ternary (printf "%s/%s" $registry $repository) $repository (ne $registry "") -}}
{{- if $azure.digest -}}
{{- printf "%s@%s" $ref $azure.digest -}}
{{- else -}}
{{- printf "%s:%s" $ref ($azure.tag | default "latest") -}}
{{- end -}}
{{- else -}}
{{- $image := index $ctx.Values.images $key -}}
{{- $registry := $image.registry | default "" -}}
{{- $repository := required "image repository is required" $image.repository -}}
{{- $ref := ternary (printf "%s/%s" $registry $repository) $repository (ne $registry "") -}}
{{- if $image.digest -}}
{{- printf "%s@%s" $ref $image.digest -}}
{{- else -}}
{{- printf "%s:%s" $ref ($image.tag | default "latest") -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Azure Marketplace usage-metering identifier. Replaced by the cluster extension
with the extension instance name at deployment time.
*/}}
{{- define "stackguard.billingLabels" -}}
{{- if .Values.global.azure }}
azure-extensions-usage-release-identifier: {{ .Release.Name | quote }}
{{- end }}
{{- end }}

{{- define "stackguard.databaseUrl" -}}
{{- if .Values.secrets.databaseUrl -}}
{{- .Values.secrets.databaseUrl -}}
{{- else -}}
{{- printf "postgresql://%s:%s@stackguard-postgres:5432/%s?sslmode=disable" .Values.secrets.postgres.user .Values.secrets.postgres.password .Values.secrets.postgres.database -}}
{{- end -}}
{{- end }}
