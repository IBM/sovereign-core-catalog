{{/*
The byop-broker passes provisioning parameters as flat top-level Helm values
(helm.valuesObject), e.g. database_name, storage_class. Each helper below
prefers the flat value and falls back to the nested chart value, so the chart
works both from the broker and from a direct `helm install`.
*/}}

{{- define "postgres-s390x.instanceName" -}}
{{- default .Release.Name (default .Values.instance.name .Values.instanceName) -}}
{{- end }}

{{- define "postgres-s390x.database" -}}
{{- default .Values.auth.database .Values.database_name -}}
{{- end }}

{{- define "postgres-s390x.username" -}}
{{- default .Values.auth.username .Values.database_user -}}
{{- end }}

{{- define "postgres-s390x.password" -}}
{{- default .Values.auth.password .Values.database_password -}}
{{- end }}

{{- define "postgres-s390x.superuserPassword" -}}
{{- default .Values.auth.superuserPassword .Values.superuser_password -}}
{{- end }}

{{- define "postgres-s390x.storageClass" -}}
{{- default .Values.persistence.storageClass .Values.storage_class -}}
{{- end }}

{{- define "postgres-s390x.storageSize" -}}
{{- default .Values.persistence.size .Values.storage_size -}}
{{- end }}
