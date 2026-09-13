{{/*
Helper templates for the emqx chart.
Resource names and selectors are fixed (not derived from the release name):
EMQX_NODE_NAME is hard-wired to the emqx-0 pod DNS name, and changing a
selector or pod-template label would restart the broker.
*/}}

{{- /*
Target namespace. Falls back to the release namespace so that `-n` ALWAYS
controls object placement: a values-file `namespace.name` that silently beat
`-n` is how a rehearsal once wrote Helm ownership annotations onto a live
production Deployment. Set namespace.name only to place objects somewhere
other than the release namespace, and never in an instance-values file.
*/ -}}
{{- define "emqx.ns" -}}
{{ .Values.namespace.name | default .Release.Namespace }}
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
