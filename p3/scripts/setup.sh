#!/usr/bin/env bash
set -euo pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"
USER_NAME="vagrant"

log() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${RESET} $*"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}



log "Updating apt index"
apt-get update -y
apt-get install -y curl git docker.io

if ! systemctl is-enabled "docker" >/dev/null 2>&1; then
    log "Enabling service: docker"
    systemctl enable "docker"
else
    log "Service already enabled: docker"
fi

if ! systemctl is-active "docker" >/dev/null 2>&1; then
    log "Starting service: docker"
    systemctl start "docker"
else
    log "Service already running: docker"
fi

if ! getent group docker >/dev/null 2>&1; then
    warn "Group docker does not exist"
    return 0
fi

if id -nG "$USER_NAME" | grep -qw "docker"; then
    log "User '$USER_NAME' is already in group 'docker'"
else
    log "Adding user '$USER_NAME' to group 'docker'"
    usermod -aG "docker" "$USER_NAME"
fi


if have_cmd kubectl; then
    log "kubectl already installed"
else
    log "Installing kubectl"
    version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl"
    chmod 0755 /usr/local/bin/kubectl
    chown root:root /usr/local/bin/kubectl
fi


if have_cmd k3d; then
    log "k3d already installed"
else
    log "Installing k3d"
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi


log "Versions:"
docker --version
k3d version
kubectl version --client=true || true
log "Tool installation complete"