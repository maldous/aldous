#!/usr/bin/env bash
set -euo pipefail
set -x

# Kong deployment now handled by Tilt k8s_yaml
# Just wait for deployment to be ready
echo "Waiting for Kong deployment to be ready..."
kubectl -n default wait --for=condition=Available deployment/kong-kong --timeout=600s
kubectl create secret tls cloudflare-origin-cert --cert=origin.crt --key=origin.key -n default --dry-run=client -o yaml | kubectl apply -f -
