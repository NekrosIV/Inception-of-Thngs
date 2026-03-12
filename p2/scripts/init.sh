#!/bin/bash
set -euo pipefail

NODE_IP="192.168.56.110"

apt-get update
apt-get install -y curl

echo "Installing K3s server on ${NODE_IP}..."

if [ ! -f /etc/systemd/system/k3s.service ]; then
  curl -sfL https://get.k3s.io | sh -s - \
    --node-ip="${NODE_IP}" \
    --write-kubeconfig-mode=644
fi

echo "K3s server installed. ✅"

echo "Waiting for K3s to be ready..."

until kubectl get nodes >/dev/null 2>&1; do
  sleep 2
done

echo "K3s is ready. ✅"

echo "Deploying applications..."

kubectl apply -f /vagrant/confs/app1.yaml
kubectl apply -f /vagrant/confs/app2.yaml
kubectl apply -f /vagrant/confs/app3.yaml

echo "Applications deployed. 🚀"