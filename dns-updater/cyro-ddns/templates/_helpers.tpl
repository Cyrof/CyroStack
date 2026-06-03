{{- define "cyro-ddns.name" -}}
cyro-ddns
{{- end -}}

{{- define "cyro-ddns.fullname" -}}
{{- printf "%s" (include "cyro-ddns.name" .) -}}
{{- end -}}
