{{- define "movement-fullnode.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "movement-fullnode.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "movement-fullnode.labels" -}}
app: {{ .Values.node.id | quote }}
movementnetwork.xyz/node: {{ .Values.node.id | quote }}
movementnetwork.xyz/node_type: "pfn"
movementnetwork.xyz/network: {{ .Values.node.network | quote }}
{{- if .Values.node.chainId }}
movementnetwork.xyz/chain_id: {{ .Values.node.chainId | quote }}
{{- end }}
{{- end -}}

{{- define "movement-fullnode.selectorLabels" -}}
app: {{ .Values.node.id | quote }}
{{- end -}}

{{- define "movement-fullnode.storageClassName" -}}
{{- if .Values.storage.className -}}
{{- .Values.storage.className -}}
{{- else if .Values.storage.create -}}
{{- printf "%s-gp3" (include "movement-fullnode.fullname" .) -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}
