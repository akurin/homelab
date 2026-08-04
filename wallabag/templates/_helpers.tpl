{{- define "wallabag.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "wallabag.labels" -}}
app.kubernetes.io/name: wallabag
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "wallabag.selectorLabels" -}}
app.kubernetes.io/name: wallabag
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
