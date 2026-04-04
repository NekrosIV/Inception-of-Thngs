#!/usr/bin/env bash
set -euo pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

USER_NAME="${SUDO_USER:-${USER:-kasingh}}"

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

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

need_root() {
    [ "${EUID}" -eq 0 ] || error "Run this script as root"
}

ensure_service_enabled_and_started() {
    local svc="$1"

    if ! systemctl is-enabled "$svc" >/dev/null 2>&1; then
        log "Enabling service: $svc"
        systemctl enable "$svc"
    else
        log "Service already enabled: $svc"
    fi

    if ! systemctl is-active "$svc" >/dev/null 2>&1; then
        log "Starting service: $svc"
        systemctl start "$svc"
    else
        log "Service already running: $svc"
    fi
}

need_root

log "Updating apt index"
apt-get update -y

log "Installing required packages"
apt-get install -y curl git docker.io ca-certificates gnupg apt-transport-https

ensure_service_enabled_and_started docker

if getent group docker >/dev/null 2>&1; then
    if id -nG "$USER_NAME" 2>/dev/null | grep -qw docker; then
        log "User '$USER_NAME' is already in group 'docker'"
    else
        log "Adding user '$USER_NAME' to group 'docker'"
        usermod -aG docker "$USER_NAME"
        warn "You may need to re-login for the docker group to apply to '$USER_NAME'"
    fi
else
    warn "Group 'docker' not found"
fi

if have_cmd kubectl; then
    log "kubectl already installed"
else
    log "Installing kubectl"
    KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    chmod 0755 /usr/local/bin/kubectl
    chown root:root /usr/local/bin/kubectl
fi

if have_cmd k3d; then
    log "k3d already installed"
else
    log "Installing k3d"
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

if have_cmd helm; then
    log "helm already installed"
else
    log "Installing helm"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

log "Versions:"
docker --version
k3d version
kubectl version --client=true || true
helm version --short || true

log "Tool installation complete"
