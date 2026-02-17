{{- define "movement-node.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "movement-node.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "movement-node.labels" -}}
app: {{ .Values.node.name | quote }}
movementnetwork.xyz/node: {{ .Values.node.name | quote }}
movementnetwork.xyz/node_type: {{ .Values.node.type | quote }}
movementnetwork.xyz/network: {{ .Values.network.name | quote }}
{{- if .Values.network.chainId }}
movementnetwork.xyz/chain_id: {{ .Values.network.chainId | quote }}
{{- end }}
{{- end -}}

{{- define "movement-node.selectorLabels" -}}
app: {{ .Values.node.name | quote }}
{{- end -}}

{{- define "movement-node.storageClassName" -}}
{{- if .Values.storage.storageClassName -}}
{{- .Values.storage.storageClassName -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}