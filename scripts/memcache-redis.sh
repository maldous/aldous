#!/usr/bin/env bash
set -euo pipefail
set -x

# Memcached and Redis deployments now handled by Tilt k8s_yaml
# Just wait for pods to be ready (they should exist via k8s_yaml)
echo "Waiting for memcached and redis pods to be ready..."
kubectl -n default wait --for=condition=Ready pod -l app.kubernetes.io/name=memcached --timeout=300s
kubectl -n default wait --for=condition=Ready pod -l app.kubernetes.io/name=redis,app.kubernetes.io/component=master --timeout=300s
