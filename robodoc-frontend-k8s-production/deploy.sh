set -e

NAMESPACE="robodoc"

# Apply manifests
kubectl apply -f secret.yaml
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Apply Filebeat DaemonSet (runs one pod per node, robodoc namespace logs only)
# kubectl apply -f filebeat/configmap.yaml
# kubectl apply -f filebeat/daemonset.yaml

# Wait for rollout to finish
kubectl -n "${NAMESPACE}" rollout restart deployment/robodoc-customer-production
kubectl -n "${NAMESPACE}" rollout status deployment/robodoc-customer-production --timeout=120s

# Restart Filebeat DaemonSet to pick up latest configmap changes
# kubectl -n "${NAMESPACE}" rollout restart daemonset/filebeat
# kubectl -n "${NAMESPACE}" rollout status daemonset/filebeat --timeout=120s

# Show what's running
kubectl -n "${NAMESPACE}" get pods,svc,configmap,daemonset
