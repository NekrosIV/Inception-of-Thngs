#!/usr/bin/env bash
set -euo pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

CLUSTER_NAME="iot"

log() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${RESET} $*"
}

if command -v helm >/dev/null 2>&1; then
    if helm status gitlab -n gitlab >/dev/null 2>&1; then
        log "Uninstalling GitLab Helm release"
        helm uninstall gitlab -n gitlab || warn "Unable to uninstall GitLab cleanly"
    else
        log "GitLab Helm release not found"
    fi
else
    warn "helm command not found"
fi

if command -v k3d >/dev/null 2>&1; then
    if k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
        log "Deleting cluster: ${CLUSTER_NAME}"
        k3d cluster delete "${CLUSTER_NAME}"
    else
        log "Cluster not found: ${CLUSTER_NAME}"
    fi
else
    warn "k3d command not found"
fi

log "Removing kube config directory"
rm -rf "${HOME}/.kube"

log "Cleanup complete"
