#!/usr/bin/env bash
# ==============================================================================
# Stop / Pause / Teardown Argo CD
#
# Usage:
#   ./stop.sh             # Safe pause: scale all Argo CD workloads to 0 replicas & stop port-forward
#   ./stop.sh --apps-only # Stop/remove Robodoc apps from Argo CD (leaves Argo CD server running)
#   ./stop.sh --purge     # Full uninstall: remove all apps, Argo CD manifests, and namespace
#   ./stop.sh --help      # Show this help message
# ==============================================================================
set -euo pipefail

NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
ACTION="pause"

# ANSI colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apps-only)
      ACTION="apps-only"
      shift
      ;;
    --purge|--uninstall)
      ACTION="purge"
      shift
      ;;
    -h|--help)
      echo -e "${BOLD}Usage:${NC}"
      echo "  $0 [options]"
      echo ""
      echo -e "${BOLD}Options:${NC}"
      echo "  (no args)        Safe Stop/Pause: scales all Argo CD deployments & statefulsets to 0"
      echo "                   replicas and stops port-forwarding. Preserves configuration & secrets."
      echo "  --apps-only      Remove Robodoc applications from Argo CD (keeps Argo CD running,"
      echo "                   and keeps your application pods running in the 'robodoc' namespace)."
      echo "  --purge          Complete teardown: uninstalls Argo CD manifests and deletes 'argocd' namespace."
      echo "  -h, --help       Show this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Run '$0 --help' for usage."
      exit 1
      ;;
  esac
done

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}${BOLD}             Stopping Argo CD                        ${NC}"
echo -e "${BLUE}======================================================${NC}"

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}[ERROR] kubectl is not installed or not in PATH.${NC}"
  exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
  echo -e "${RED}[ERROR] Cannot connect to the Kubernetes cluster. Please check your kubeconfig.${NC}"
  exit 1
fi

if ! kubectl get namespace "${NAMESPACE}" &> /dev/null; then
  echo -e "${YELLOW}Namespace '${NAMESPACE}' does not exist. Nothing to stop.${NC}"
  exit 0
fi

# Function to stop any local port-forwarding processes
stop_port_forward() {
  local pids
  pids=$(pgrep -f "port-forward.*argocd-server" 2>/dev/null || true)
  if [[ -n "${pids}" ]]; then
    echo -e "${YELLOW}Stopping active Argo CD port-forwarding processes (PIDs: ${pids})...${NC}"
    kill ${pids} 2>/dev/null || true
  fi
}

case "${ACTION}" in
  pause)
    echo -e "${YELLOW}Mode: Safe Stop / Pause (scale workloads to 0)${NC}"
    
    stop_port_forward
    
    echo -e "${YELLOW}Scaling all deployments in '${NAMESPACE}' namespace to 0 replicas...${NC}"
    kubectl scale deployment --all -n "${NAMESPACE}" --replicas=0
    
    echo -e "${YELLOW}Scaling statefulsets in '${NAMESPACE}' namespace to 0 replicas...${NC}"
    if kubectl get statefulset -n "${NAMESPACE}" &> /dev/null; then
      kubectl scale statefulset --all -n "${NAMESPACE}" --replicas=0 2>/dev/null || true
    fi
    
    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}${BOLD}             Argo CD has been Paused                  ${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo "All Argo CD pods are stopped. Zero CPU/RAM is consumed and no auto-sync is active."
    echo "All configurations, secrets, and applications remain preserved in the cluster."
    echo ""
    echo -e "${BOLD}To start/resume Argo CD again:${NC}"
    echo "  ${SCRIPT_DIR}/run.sh"
    ;;

  apps-only)
    echo -e "${YELLOW}Mode: Stopping / Removing Robodoc Applications from Argo CD${NC}"
    
    if [[ -f "${SCRIPT_DIR}/robodoc-backend-application.yaml" ]]; then
      kubectl delete -f "${SCRIPT_DIR}/robodoc-backend-application.yaml" --ignore-not-found
    fi
    if [[ -f "${SCRIPT_DIR}/robodoc-customer-application.yaml" ]]; then
      kubectl delete -f "${SCRIPT_DIR}/robodoc-customer-application.yaml" --ignore-not-found
    fi
    if [[ -f "${SCRIPT_DIR}/robodoc-project.yaml" ]]; then
      kubectl delete -f "${SCRIPT_DIR}/robodoc-project.yaml" --ignore-not-found
    fi
    
    echo ""
    echo -e "${GREEN}Robodoc applications removed from Argo CD.${NC}"
    echo "Note: Underlying workloads in 'robodoc' namespace were NOT deleted."
    echo ""
    echo -e "${BOLD}Remaining applications in Argo CD:${NC}"
    kubectl get applications -n "${NAMESPACE}" 2>/dev/null || echo "None"
    ;;

  purge)
    echo -e "${RED}${BOLD}Mode: Complete Purge / Teardown${NC}"
    stop_port_forward
    
    echo -e "${YELLOW}[1/3] Removing all Argo CD Applications...${NC}"
    kubectl delete applications --all -n "${NAMESPACE}" --ignore-not-found
    
    echo -e "${YELLOW}[2/3] Deleting Argo CD manifests...${NC}"
    kubectl delete -n "${NAMESPACE}" -f "${ARGOCD_MANIFEST_URL}" --ignore-not-found || true
    
    echo -e "${YELLOW}[3/3] Deleting '${NAMESPACE}' namespace...${NC}"
    kubectl delete namespace "${NAMESPACE}" --ignore-not-found
    
    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}${BOLD}     Argo CD Completely Removed from Cluster          ${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo "To reinstall and start Argo CD from scratch, run:"
    echo "  ${SCRIPT_DIR}/run.sh"
    ;;
esac
