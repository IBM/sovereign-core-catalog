#!/usr/bin/env bash
# scaffold.sh — create the directory skeleton for a new Helm service definition
# Usage: scaffold.sh <service-dir>  e.g. scaffold.sh services/foohelm/v1
set -euo pipefail

SERVICE_DIR="${1:?usage: scaffold.sh <service-dir>}"

mkdir -p \
  "$SERVICE_DIR/argocd" \
  "$SERVICE_DIR/catalog" \
  "$SERVICE_DIR/chart/templates" \
  "$SERVICE_DIR/template"

# catalog/metrics.json — must be a JSON object with a metrics array
cat > "$SERVICE_DIR/catalog/metrics.json" <<'EOF'
{"metrics": []}
EOF

# catalog/catalog.yaml — placeholder
cat > "$SERVICE_DIR/catalog/catalog.yaml" <<'EOF'
name: PLACEHOLDER
display_name: PLACEHOLDER
description: PLACEHOLDER
plans:
  - id: standard
    name: Standard
    description: Standard deployment with persistent storage and auto-generated credentials
  - id: PLACEHOLDER_plan
    name: Default
    description: Default deployment with persistent storage and auto-generated credentials
EOF

# catalog/schema.json — minimal valid JSON Schema
cat > "$SERVICE_DIR/catalog/schema.json" <<'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "title": "PLACEHOLDER Instance Parameters",
  "description": "Parameters for provisioning a PLACEHOLDER instance",
  "properties": {
    "cluster_url": {
      "type": "string",
      "description": "Target cluster server URL (optional, defaults to broker's cluster). Must be a registered ArgoCD cluster.",
      "format": "uri",
      "pattern": "^https://.*",
      "examples": [
        "https://kubernetes.default.svc",
        "https://192.168.2.89:6443"
      ]
    }
  },
  "required": [],
  "additionalProperties": false
}
EOF

# argocd/applicationset-helm.yaml.tmpl — canonical inline template
# selfHeal: true enforces the GitOps contract — ArgoCD reverts any manual cluster change
cat > "$SERVICE_DIR/argocd/applicationset-helm.yaml.tmpl" <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: SERVICE_NAME-app-set
  namespace: ARGOCD_NAMESPACE
  labels:
    app: SERVICE_NAME
    service-type: SERVICE_TYPE
spec:
  generators:
    - git:
        files:
          - path: "instances/SERVICE_NAME/*/metadata.yaml"
        repoURL: GITOPS_REPO_URL
        revision: GITOPS_REPO_REVISION
  syncPolicy:
    preserveResourcesOnDeletion: false
  template:
    metadata:
      labels:
        app: SERVICE_NAME
        service-type: SERVICE_TYPE
        instance: "{{ instance_name }}"
      name: "{{ service_type }}-{{ instance_name }}"
    spec:
      destination:
        server: "{{ cluster_url }}"
        namespace: "{{ namespace }}"
      project: ARGOCD_PROJECT
      source:
        path: services/SERVICE_NAME/SERVICE_VERSION/chart
        helm:
          valueFiles:
            - ../../../../instances/SERVICE_NAME/{{ instance_name }}/values.yaml
        repoURL: GITOPS_REPO_URL
        targetRevision: GITOPS_REPO_REVISION
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
EOF

# imagesetconfiguration.yaml — placeholder
cat > "$SERVICE_DIR/imagesetconfiguration.yaml" <<'EOF'
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v1alpha2
storageConfig:
  local:
    path: ./metadata
mirror:
  additionalImages:
    # Latest stable: docker.io/PLACEHOLDER:LATEST_TAG
    - name: docker.io/PLACEHOLDER:TAG
EOF

# template/values.yaml.tmpl — standard skeleton
# BYOP_REGISTRY is a literal string substituted by service-render --mapping image-mapping.txt
# via the line "BYOP_REGISTRY -> <hostname>" at the top of image-mapping.txt.
# values-test.yaml MUST use the upstream registry directly (never BYOP_REGISTRY).
cat > "$SERVICE_DIR/template/values.yaml.tmpl" <<'EOF'
# Helm values override for PLACEHOLDER instance
namespaceOverride: {{ namespace }}

commonLabels:
  app: PLACEHOLDER
  service-type: PLACEHOLDER

commonAnnotations:
  sovcore.byop.ibm.com/crn: {{ context.crn | default("crn:unknown") | yaml_safe }}
  sovcore.byop.ibm.com/account-id: {{ context.account_id | default("unknown") | yaml_safe }}
  sovcore.byop.ibm.com/sub-account-id: {{ context.sub_account_id | default("unknown") | yaml_safe }}
  sovcore.byop.ibm.com/platform: {{ context.platform | default("unknown") | yaml_safe }}

instance:
  name: {{ instance_name }}
  id: "{{ instance_id }}"
  environment: {{ environment }}
  clusterName: "{{ cluster_name }}"

imagePullSecrets:
{% if image_pull_secret_name %}
  - name: {{ image_pull_secret_name }}
{% else %}
  []
{% endif %}

image:
  registry: BYOP_REGISTRY
  repository: byop/PLACEHOLDER
  tag: "TAG"
EOF

# chart/Chart.yaml — placeholder
cat > "$SERVICE_DIR/chart/Chart.yaml" <<'EOF'
apiVersion: v2
name: PLACEHOLDER
description: A Helm chart for PLACEHOLDER on Kubernetes / OpenShift
type: application
keywords:
  - PLACEHOLDER
maintainers:
  - name: BYOP
    url: https://github.com/IBM/byop-sample-repo
version: "1.0.0"
appVersion: "0.0.0"
EOF

echo ""
echo "✓ Scaffolded $SERVICE_DIR"
echo ""
echo "Files created:"
find "$SERVICE_DIR" -type f | sort | sed 's/^/  /'
echo ""
echo "Next: fill in all PLACEHOLDER values and add the chart templates."
echo "      See .bob/skills/new-helm-service/SKILL.md for the full checklist."
