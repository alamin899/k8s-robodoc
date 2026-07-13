#!/usr/bin/env bash
# Stop Filebeat.
#
# Usage:
#   ./stop.sh          # stop log collection (delete DaemonSet, keep config + RBAC)
#   ./stop.sh --purge  # full teardown (also remove ConfigMap, SA, ClusterRole, binding)
#
# Filebeat is a DaemonSet, so it has no "replicas" to scale to 0 — the way to
# stop it is to delete the DaemonSet, which terminates its pod on every node.
set -e

NAMESPACE="robodoc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Stopping Filebeat DaemonSet in namespace '${NAMESPACE}'..."
kubectl -n "${NAMESPACE}" delete daemonset filebeat --ignore-not-found

if [[ "${1:-}" == "--purge" ]]; then
  echo "Purging Filebeat ConfigMap and RBAC..."
  # ClusterRole/ClusterRoleBinding are cluster-scoped (no namespace flag).
  kubectl delete -f "${SCRIPT_DIR}/daemonset.yaml" --ignore-not-found
  kubectl delete -f "${SCRIPT_DIR}/configmap.yaml" --ignore-not-found
fi

echo "Done. Remaining Filebeat resources (should be empty if purged):"
kubectl -n "${NAMESPACE}" get daemonset,configmap -l app=filebeat --ignore-not-found
