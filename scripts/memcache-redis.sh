#!/usr/bin/env bash
set -euo pipefail
set -x

microk8s helm repo add bitnami https://charts.bitnami.com/bitnami
microk8s helm repo update
microk8s helm install memcached bitnami/memcached 
microk8s helm upgrade --install redis bitnami/redis --set architecture=standalone --set auth.enabled=false --set master.persistence.storageClass=ceph-rbd --set master.persistence.size=3Gi
