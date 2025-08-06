#!/usr/bin/env bash
set -euo pipefail
set -x

# Copy MinIO secrets to default namespace for Keycloak
kubectl get secret microk8s-user-1 -n minio-operator -o yaml | sed 's/namespace: minio-operator/namespace: default/' | kubectl apply -f - || echo "Secret already exists, continuing..."

# Keycloak deployment now handled by Tilt k8s_yaml
# Wait for StatefulSet to be ready
echo "Waiting for Keycloak StatefulSet to be ready..."
kubectl -n default wait --for=condition=Ready statefulset/keycloak --timeout=600s
kubectl apply -f k8s/oidc-user.yaml
kubectl apply -f k8s/oidc-protection.yaml
