{{/*
Helper templates for the emqx chart.
Resource names and selectors are fixed (not derived from the release name):
EMQX_NODE_NAME is hard-wired to the emqx-0 pod DNS name, and changing a
selector or pod-template label would restart the broker.
*/}}

{{- define "emqx.ns" -}}
{{ .Values.namespace.name }}
{{- end -}}

{{/* `annotations:` block with the keep policy, or nothing. */}}
{{- define "emqx.keepAnnotations" -}}
{{- if .Values.keepOnUninstall -}}
annotations:
  helm.sh/resource-policy: keep
{{- end -}}
{{- end -}}

{{/* storageClassName for a PVC: its own override or the global default. */}}
{{- define "emqx.storageClass" -}}
{{- $ctx := index . 0 -}}
{{- $override := index . 1 -}}
{{ default $ctx.Values.storageClassName $override }}
{{- end -}}
