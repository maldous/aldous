#!/usr/bin/env bash
set -euo pipefail
set -x

microk8s enable minio -s ceph-rbd -c 20Gi
until kubectl get pods -n minio-operator -l v1.min.io/tenant=microk8s --no-headers 2>/dev/null | grep -q .; do sleep 1; done
kubectl -n minio-operator wait --for=condition=Ready pod -l v1.min.io/tenant=microk8s --timeout=600s
MINIO_ACCESS=$(kubectl -n minio-operator get secret microk8s-user-1 -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
MINIO_SECRET=$(kubectl -n minio-operator get secret microk8s-user-1 -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)
kubectl run mc-bucket --image=minio/mc --restart=Never --rm -it --env "MC_HOST_local=http://${MINIO_ACCESS}:${MINIO_SECRET}@${MINIO_HOST}:9000" --command -- mc mb local/keycloak-bucket --ignore-existing
kubectl run mc-bucket --image=minio/mc --restart=Never --rm -it --env "MC_HOST_local=http://${MINIO_ACCESS}:${MINIO_SECRET}@${MINIO_HOST}:9000" --command -- mc mb local/aldous-bucket --ignore-existing
