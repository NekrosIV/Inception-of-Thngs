#!/usr/bin/env bash
set -euo pipefail

TRAEFIK_IP="$(kubectl get svc traefik -n kube-system -o jsonpath='{.spec.clusterIP}')"
CURRENT="$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.NodeHosts}')"

echo "${CURRENT}" | grep -q " gitlab.local.com" && exit 0

UPDATED="$(printf '%s\n%s %s\n' "${CURRENT}" "${TRAEFIK_IP}" "gitlab.local.com")"
PATCH="$(printf '%s' "${UPDATED}" | python3 -c 'import json,sys; print(json.dumps({"data":{"NodeHosts": sys.stdin.read()}}))')"

kubectl patch configmap coredns -n kube-system --type merge -p "${PATCH}"
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system --timeout=120s