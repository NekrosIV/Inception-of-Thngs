#!/usr/bin/env bash
set -euo pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

CLUSTER_NAME="iot2"
ARGOCD_NAMESPACE="argocd"
GITLAB_NAMESPACE="gitlab"
DEV_NAMESPACE="dev"

VALUES_FILE="./confs/gitlab-values.yaml"
ARGOCD_INGRESS_FILE="./confs/argocd_ingress.yaml"
ARGOCD_APP_FILE="./confs/app_argocd.yaml"
TIMEOUT="1800s"

log() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${RESET} $*"
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

    if kubectl get namespace "$ns" >/dev/null 2>&1; then
        log "Namespace already exists: $ns"
    else
        log "Creating namespace: $ns"
        kubectl create namespace "$ns"
    fi
}

wait_for_deployments() {
    local ns="$1"
    kubectl wait --for=condition=Available deployment --all -n "$ns" --timeout=600s
}

require_cmd docker
require_cmd k3d
require_cmd kubectl
require_cmd helm

docker info >/dev/null 2>&1 || error "Docker daemon not available"

if k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
    log "Cluster already exists: ${CLUSTER_NAME}"
else
    log "Creating cluster: ${CLUSTER_NAME}"
    k3d cluster create "${CLUSTER_NAME}" \
        -p "80:80@loadbalancer"
fi

log "Checking cluster access"
kubectl cluster-info >/dev/null 2>&1 || error "kubectl cannot reach the cluster"

ensure_namespace "${DEV_NAMESPACE}"
ensure_namespace "${ARGOCD_NAMESPACE}"
ensure_namespace "${GITLAB_NAMESPACE}"

log "Installing Argo CD"
kubectl apply --server-side -n "${ARGOCD_NAMESPACE}" \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log "Configuring Argo CD server in insecure mode for Traefik HTTP backend"
kubectl patch configmap argocd-cmd-params-cm \
    -n "${ARGOCD_NAMESPACE}" \
    --type merge \
    -p '{"data":{"server.insecure":"true"}}' || true

log "Restarting argocd-server"
kubectl rollout restart deployment/argocd-server -n "${ARGOCD_NAMESPACE}" || true
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=600s || true

log "Waiting for Argo CD deployments"
wait_for_deployments "${ARGOCD_NAMESPACE}"

if [ -f "${ARGOCD_INGRESS_FILE}" ]; then
    log "Applying Argo CD ingress"
    kubectl apply -f "${ARGOCD_INGRESS_FILE}"
else
    warn "Argo CD ingress file not found: ${ARGOCD_INGRESS_FILE}"
fi

[ -f "${VALUES_FILE}" ] || error "Missing values file: ${VALUES_FILE}"

log "Adding GitLab Helm repository"
helm repo add gitlab https://charts.gitlab.io/ >/dev/null 2>&1 || true
helm repo update >/dev/null

log "Installing or upgrading GitLab"
helm upgrade --install gitlab gitlab/gitlab \
    -n "${GITLAB_NAMESPACE}" \
    -f "${VALUES_FILE}" \
    --timeout 30m

log "Waiting for GitLab jobs..."
until kubectl get jobs -n "${GITLAB_NAMESPACE}" | grep -E 'gitlab-migrations-|gitlab-minio-create-buckets-' >/dev/null 2>&1; do
    kubectl get pods -n "${GITLAB_NAMESPACE}" || true
    sleep 5
done

until kubectl get jobs -n "${GITLAB_NAMESPACE}" | grep 'gitlab-migrations-' | grep '1/1' >/dev/null 2>&1; do
    kubectl get jobs -n "${GITLAB_NAMESPACE}" || true
    sleep 5
done

until kubectl get jobs -n "${GITLAB_NAMESPACE}" | grep 'gitlab-minio-create-buckets-' | grep '1/1' >/dev/null 2>&1; do
    kubectl get jobs -n "${GITLAB_NAMESPACE}" || true
    sleep 5
done

until kubectl get pods -n "${GITLAB_NAMESPACE}" | grep 'gitlab-webservice-default-' | grep '2/2' | grep 'Running' >/dev/null 2>&1; do
    kubectl get pods -n "${GITLAB_NAMESPACE}" || true
    sleep 5
done

until kubectl get pods -n "${GITLAB_NAMESPACE}" | grep 'gitlab-sidekiq-all-in-1-v2-' | grep '1/1' | grep 'Running' >/dev/null 2>&1; do
    kubectl get pods -n "${GITLAB_NAMESPACE}" || true
    sleep 5
done

until kubectl get secret -n "${GITLAB_NAMESPACE}" gitlab-gitlab-initial-root-password >/dev/null 2>&1; do
    kubectl get pods -n "${GITLAB_NAMESPACE}" || true
    sleep 5
done


kubectl get pods -n "${GITLAB_NAMESPACE}"

if [ -f "${ARGOCD_APP_FILE}" ]; then
    log "Applying Argo CD application linked to GitLab repo"
    kubectl apply -f "${ARGOCD_APP_FILE}"
else
    warn "Argo CD application file not found: ${ARGOCD_APP_FILE}"
fi

ARGOCD_PASSWORD="$(kubectl get secret argocd-initial-admin-secret \
    -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || true)"

GITLAB_PASSWORD="$(kubectl get secret gitlab-gitlab-initial-root-password \
    -n "${GITLAB_NAMESPACE}" \
    -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || true)"

log "Init complete"
log "Argo CD namespace : ${ARGOCD_NAMESPACE}"
log "GitLab namespace  : ${GITLAB_NAMESPACE}"
log "Argo CD user      : admin"
log "Argo CD password  : ${ARGOCD_PASSWORD:-unavailable}"
log "GitLab user       : root"
log "GitLab password   : ${GITLAB_PASSWORD}"
log "Check ingress with: kubectl get ingress -A"
