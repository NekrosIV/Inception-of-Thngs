#!/usr/bin/env bash
set -euo pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

NAMESPACE="argocd"
CLUSTER_NAME="iot"

log() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

error() {
    echo -e "${RED}[ERROR]${RESET} $*" >&2
    exit 1
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || error "Missing command: $cmd"
}

ensure_namespace() {
    local ns="$1"

    if  kubectl get namespace "$ns" >/dev/null 2>&1; then
        log "Namespace already exists: $ns"
    else
        log "Creating namespace: $ns"
        kubectl create namespace "$ns"
    fi
}

require_cmd docker
require_cmd k3d
require_cmd kubectl

docker info >/dev/null 2>&1 || error "Docker daemon not available"

if k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
    log "Cluster already exists: ${CLUSTER_NAME}"
else
    log "Creating cluster: ${CLUSTER_NAME}"
    k3d cluster create "${CLUSTER_NAME}" \
         -p "6443:443@loadbalancer" \
         -p "8080:80@loadbalancer" \
         -p "6767:6767@loadbalancer"
fi

log "Checking cluster access"
kubectl cluster-info
ensure_namespace dev
ensure_namespace ${NAMESPACE}

log "Installing Argo CD..."
kubectl apply --server-side -n ${NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log "Waiting for Argo CD components to become ready..."
kubectl wait --for=condition=Available deployment --all -n "${NAMESPACE}" --timeout=300s

log "Retrieving initial admin password..."
ARGOCD_PASSWORD="$(kubectl get secret argocd-initial-admin-secret \
  -n "${NAMESPACE}" \
  -o jsonpath='{.data.password}' | base64 -d)"

log "apply app_argocd.yaml and argocd_ingress.yaml"
kubectl apply -f ./confs/app_argocd.yaml
kubectl apply -f ./confs/argocd_ingress.yaml
log "Argo CD installed successfully."
log "Namespace : ${NAMESPACE}"
log "Username  : admin"
log "Password  : ${ARGOCD_PASSWORD}"

log "Init complete"
# kubectl port-forward svc/argocd-server -n ${NAMESPACE} 8080:443