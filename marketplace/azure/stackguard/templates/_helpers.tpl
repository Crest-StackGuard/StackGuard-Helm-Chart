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

{{/*
Empty namespace -> the release namespace. The Azure Marketplace cluster
extension owns its namespace and leaves namespace empty.
*/}}
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
A tag (or digest) is required: never fall back to a moving or guessed tag.
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
{{- printf "%s:%s" $ref (required (printf "global.azure.images.%s.tag is required" $key) $azure.tag) -}}
{{- end -}}
{{- else -}}
{{- $image := index $ctx.Values.images $key -}}
{{- $registry := $image.registry | default "" -}}
{{- $repository := required (printf "images.%s.repository is required" $key) $image.repository -}}
{{- $ref := ternary (printf "%s/%s" $registry $repository) $repository (ne $registry "") -}}
{{- if $image.digest -}}
{{- printf "%s@%s" $ref $image.digest -}}
{{- else -}}
{{- printf "%s:%s" $ref (required (printf "images.%s.tag is required" $key) $image.tag) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Azure Marketplace usage-metering identifier. Replaced by the cluster extension
with the extension instance name at deployment time. Emitted only when
global.azure is set, so plain Helm installs are unaffected.
*/}}
{{- define "stackguard.billingLabels" -}}
{{- if .Values.global.azure }}
azure-extensions-usage-release-identifier: {{ .Release.Name | quote }}
{{- end }}
{{- end }}

{{- define "stackguard.databaseUrl" -}}
{{- if .Values.secrets.databaseUrl -}}
{{- .Values.secrets.databaseUrl -}}
{{- else if .Values.postgres.enabled -}}
{{- printf "postgresql://%s:%s@stackguard-postgres:5432/%s?sslmode=disable" .Values.secrets.postgres.user .Values.secrets.postgres.password .Values.secrets.postgres.database -}}
{{- else -}}
{{- fail "postgres.enabled is false — set secrets.databaseUrl to your managed or external Postgres URL" -}}
{{- end -}}
{{- end }}

{{- define "stackguard.redisUrl" -}}
{{- if .Values.secrets.redisUrl -}}
{{- .Values.secrets.redisUrl -}}
{{- else if .Values.valkey.enabled -}}
{{- printf "redis://%s:%s@stackguard-valkey:%v/0" .Values.secrets.valkey.user .Values.secrets.valkey.password .Values.valkey.service.port -}}
{{- else -}}
{{- fail "valkey.enabled is false — set secrets.redisUrl to your managed Redis-compatible cache URL" -}}
{{- end -}}
{{- end }}

{{/*
Public URL for a component: explicit url, else its Azure DNS name
(<azureDnsLabel>.<global.azureRegion>.cloudapp.azure.com), else localhost.
*/}}
{{- define "stackguard.publicUrl" -}}
{{- $region := .ctx.Values.global.azureRegion -}}
{{- if .url -}}
{{- .url -}}
{{- else if and .service.azureDnsLabel $region -}}
{{- printf "http://%s.%s.cloudapp.azure.com:%v" .service.azureDnsLabel $region .service.port -}}
{{- else -}}
{{- printf "http://localhost:%v" .service.port -}}
{{- end -}}
{{- end }}

{{/*
TCP liveness/readiness probes for an HTTP container on .port.
*/}}
{{- define "stackguard.tcpProbes" -}}
livenessProbe:
  tcpSocket:
    port: {{ .port }}
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3
readinessProbe:
  tcpSocket:
    port: {{ .port }}
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3
{{- end }}
