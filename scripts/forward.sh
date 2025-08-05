#!/usr/bin/env bash
set -euo pipefail
set -x

nohup kubectl port-forward -n minio-operator svc/microk8s-hl 9000:9000 & disown
nohup kubectl port-forward -n default svc/redis-master 6379:6379 & disown
nohup kubectl port-forward -n default pod/pg-cluster-1 5432:5432 & disown
nohup kubectl port-forward -n default svc/memcached 11211:11211 & disown
