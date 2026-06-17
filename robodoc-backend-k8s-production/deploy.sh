#!/usr/bin/env bash
# Simple deploy script. Applies configmap + deployment + service.
# Run regcred.sh first if the registry secret doesn't exist yet.
set -e

NAMESPACE="robodoc"

# kubectl label node robodoc-prod-worker-2 robodoc-backend-production=true
# kubectl label node robodoc-prod-worker-2 robodoc-backend-production-

# Make sure namespace exists
# kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Ensure registry pull secret exists first
# ./regcred.sh

# ---------------------------------------------------------------------------
# Filebeat reads ELASTICSEARCH_HOST, ELASTICSEARCH_PORT, ELASTICSEARCH_USER
# from the robodoc-backend-production ConfigMap, and ELASTICSEARCH_PASSWORD
# from the robodoc-backend-production Secret — no extra secret needed.
# ---------------------------------------------------------------------------

# Apply manifests
kubectl apply -f secret.yaml
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Apply Filebeat DaemonSet (runs one pod per node, robodoc namespace logs only)
kubectl apply -f filebeat-configmap.yaml
kubectl apply -f filebeat-daemonset.yaml

# Wait for rollout to finish
kubectl -n "${NAMESPACE}" rollout restart deployment/robodoc-backend-production
kubectl -n "${NAMESPACE}" rollout status deployment/robodoc-backend-production --timeout=120s

# Restart Filebeat DaemonSet to pick up latest configmap changes
kubectl -n "${NAMESPACE}" rollout restart daemonset/filebeat
kubectl -n "${NAMESPACE}" rollout status daemonset/filebeat --timeout=120s

# Show what's running
kubectl -n "${NAMESPACE}" get pods,svc,configmap,daemonset
