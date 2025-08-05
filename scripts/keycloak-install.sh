#!/usr/bin/env bash
set -euo pipefail
set -x

MINIO_ACCESS=$(kubectl -n minio-operator get secret microk8s-user-1 -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
MINIO_SECRET=$(kubectl -n minio-operator get secret microk8s-user-1 -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)

helm upgrade --install keycloak bitnami/keycloak \
  --set proxy=edge \
  --set hostname=auth.aldous.info \
  --set ingress.enabled=true \
  --set ingress.ingressClassName=kong \
  --set ingress.hostname=auth.aldous.info \
  --set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt-staging \
  --set ingress.tls=true \
  --set ingress.existingSecret=aldous-tls \
  --set auth.adminUser=admin \
  --set auth.adminPassword=changeme \
  --set postgresql.enabled=false \
  --set externalDatabase.host=${PG_HOST} \
  --set externalDatabase.user=keycloak \
  --set externalDatabase.password=keycloak \
  --set externalDatabase.database=keycloak \
  --set cache.enabled=true \
  --set cache.type=redis \
  --set cache.redis.host=redis-master.default.svc.cluster.local \
  --set persistence.enabled=true \
  --set persistence.size=5Gi \
  --set persistence.storageClass=ceph-rbd \
  --set extraEnv[0].name=KC_SPI_STORAGE_S3_BUCKET \
  --set extraEnv[0].value=keycloak-bucket \
  --set extraEnv[1].name=KC_SPI_STORAGE_S3_ENDPOINT \
  --set extraEnv[1].value="http://${MINIO_HOST}:9000" \
  --set extraEnv[2].name=KC_SPI_STORAGE_S3_ACCESSKEY \
  --set extraEnv[2].value=${MINIO_ACCESS} \
  --set extraEnv[3].name=KC_SPI_STORAGE_S3_SECRETKEY \
  --set extraEnv[3].value=${MINIO_SECRET}
kubectl -n default wait --for=condition=Ready pod/keycloak-0 --timeout=600s
kubectl apply -f k8s/oidc-user.yaml
kubectl apply -f k8s/oidc-protection.yaml
