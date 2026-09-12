#!/usr/bin/env bash
# ==============================================================================
# Run / Start Argo CD and Robodoc GitOps Applications
#
# Usage:
#   ./run.sh                  # Start Argo CD (install or resume if paused) & apply apps
#   ./run.sh --port-forward   # Start Argo CD and launch port-forwarding (8080:443)
#   ./run.sh --skip-apps      # Start Argo CD server components only, do not apply apps
#   ./run.sh --help           # Show this help message
# ==============================================================================
set -euo pipefail

NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
PORT_FORWARD=false
SKIP_APPS=false

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
    -p|--port-forward)
      PORT_FORWARD=true
      shift
      ;;
    --skip-apps)
      SKIP_APPS=true
      shift
      ;;
    -h|--help)
      echo -e "${BOLD}Usage:${NC}"
      echo "  $0 [options]"
      echo ""
      echo -e "${BOLD}Options:${NC}"
      echo "  -p, --port-forward   Automatically start kubectl port-forward (8080:443) after startup"
      echo "  --skip-apps          Install/start Argo CD components without applying Robodoc apps"
      echo "  -h, --help           Show this help message"
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
echo -e "${BLUE}${BOLD}        Starting Argo CD GitOps Environment          ${NC}"
echo -e "${BLUE}======================================================${NC}"

# 1. Check prerequisites
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}[ERROR] kubectl is not installed or not in PATH.${NC}"
  exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
  echo -e "${RED}[ERROR] Cannot connect to the Kubernetes cluster. Please check your kubeconfig.${NC}"
  exit 1
fi

# 2. Check if Argo CD namespace exists
if ! kubectl get namespace "${NAMESPACE}" &> /dev/null; then
  echo -e "${YELLOW}[1/4] Namespace '${NAMESPACE}' not found. Creating namespace...${NC}"
  kubectl create namespace "${NAMESPACE}"
  echo -e "${YELLOW}Installing official Argo CD stable release...${NC}"
  kubectl apply -n "${NAMESPACE}" --server-side --force-conflicts -f "${ARGOCD_MANIFEST_URL}"
else
  echo -e "${GREEN}[1/4] Namespace '${NAMESPACE}' exists.${NC}"
  
  # Check if deployments are currently installed
  if ! kubectl get deployment argocd-server -n "${NAMESPACE}" &> /dev/null; then
    echo -e "${YELLOW}Argo CD deployments not found. Installing official Argo CD stable release...${NC}"
    kubectl apply -n "${NAMESPACE}" --server-side --force-conflicts -f "${ARGOCD_MANIFEST_URL}"
  else
    # Check if deployments were paused / scaled down to 0
    SERVER_REPLICAS=$(kubectl get deployment argocd-server -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [[ "${SERVER_REPLICAS}" == "0" ]]; then
      echo -e "${YELLOW}Argo CD workloads are currently paused. Resuming workloads (scaling to 1 replica)...${NC}"
      kubectl scale deployment --all -n "${NAMESPACE}" --replicas=1
      kubectl scale statefulset --all -n "${NAMESPACE}" --replicas=1
    else
      echo -e "${GREEN}Argo CD workloads are already installed and running.${NC}"
    fi
  fi
fi

# 3. Wait for Argo CD components to be ready
echo -e "${YELLOW}[2/4] Waiting for Argo CD deployments & statefulsets to become ready...${NC}"
kubectl wait --for=condition=available deployment --all -n "${NAMESPACE}" --timeout=180s
if kubectl get statefulset argocd-application-controller -n "${NAMESPACE}" &> /dev/null; then
  kubectl rollout status statefulset/argocd-application-controller -n "${NAMESPACE}" --timeout=180s
fi
echo -e "${GREEN}Argo CD components are healthy and ready.${NC}"

# 4. Apply Robodoc GitOps project & applications
if [[ "${SKIP_APPS}" == "false" ]]; then
  echo -e "${YELLOW}[3/4] Applying Robodoc AppProject and Application manifests...${NC}"
  if [[ -f "${SCRIPT_DIR}/robodoc-project.yaml" ]]; then
    kubectl apply -f "${SCRIPT_DIR}/robodoc-project.yaml"
  fi
  if [[ -f "${SCRIPT_DIR}/robodoc-backend-application.yaml" ]]; then
    kubectl apply -f "${SCRIPT_DIR}/robodoc-backend-application.yaml"
  fi
  if [[ -f "${SCRIPT_DIR}/robodoc-customer-application.yaml" ]]; then
    kubectl apply -f "${SCRIPT_DIR}/robodoc-customer-application.yaml"
  fi
  echo -e "${GREEN}Robodoc Argo CD applications applied successfully.${NC}"
else
  echo -e "${YELLOW}[3/4] Skipping application manifests (--skip-apps specified).${NC}"
fi

# 5. Fetch Initial Admin Password
echo -e "${YELLOW}[4/4] Retrieving Argo CD admin credentials...${NC}"
ADMIN_PASSWORD=""
if kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret &> /dev/null; then
  ADMIN_PASSWORD=$(kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "")
fi

echo ""
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}${BOLD}           Argo CD is Running and Ready!              ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "${BOLD}Web UI URL:${NC}        https://localhost:8080"
echo -e "${BOLD}Username:${NC}          admin"
if [[ -n "${ADMIN_PASSWORD}" ]]; then
  echo -e "${BOLD}Initial Password:${NC}  ${ADMIN_PASSWORD}"
else
  echo -e "${YELLOW}Initial Password:${NC}  (argocd-initial-admin-secret has been removed or rotated)"
fi
echo ""
echo -e "${BOLD}Active Applications in Argo CD:${NC}"
kubectl get applications -n "${NAMESPACE}" 2>/dev/null || echo "No applications found."
echo ""
echo -e "${BOLD}Port-Forward Command:${NC}"
echo "  kubectl port-forward svc/argocd-server -n ${NAMESPACE} 8080:443"
echo ""

# Handle port-forwarding
if [[ "${PORT_FORWARD}" == "true" ]]; then
  echo -e "${BLUE}Starting port-forwarding on https://localhost:8080 (Ctrl+C to stop port-forward)...${NC}"
  kubectl port-forward svc/argocd-server -n "${NAMESPACE}" 8080:443
fi
