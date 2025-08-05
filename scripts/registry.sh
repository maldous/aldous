#!/usr/bin/env bash
set -euo pipefail
set -x

microk8s enable registry --storageclass cephfs
kubectl patch storageclass ceph-rbd -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl -n container-registry rollout status deployment/registry --timeout=600s
