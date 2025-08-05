#!/usr/bin/env bash
set -euo pipefail
set -x

export METALLB_RANGE="192.168.1.240-192.168.1.250"
export PG_HOST=pg-cluster-rw.default.svc.cluster.local
export MINIO_HOST=microk8s-hl.minio-operator.svc.cluster.local
export IMAGE_NAME="localhost:32000/kong-oidc"
export IMAGE_TAG="3.7.0"

cd scripts &&\
./reset.sh &&\
./install.sh &&\
./ceph.sh &&\
./registry.sh &&\
./minio.sh &&\
./pg.sh &&\
./memcache-redis.sh &&\
./kong.sh &&\
./keycloak-install.sh &&\
./keycloak-configure.sh &&\
./aldous.sh &&\
./forward.sh &&\
cd ..
