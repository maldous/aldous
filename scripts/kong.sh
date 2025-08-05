#!/usr/bin/env bash
set -euo pipefail
set -x

docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f docker../Dockerfile.kong .
docker push ${IMAGE_NAME}:${IMAGE_TAG}
microk8s helm repo add kong https://charts.konghq.com || true
microk8s helm repo update
microk8s helm show crds kong/kong | kubectl apply -f -
for c in $(kubectl get crd | awk '/konghq.com/ {print $1}'); do
  kubectl label crd "$c" app.kubernetes.io/managed-by=Helm --overwrite
  kubectl annotate crd "$c" meta.helm.sh/release-name=kong meta.helm.sh/release-namespace=default --overwrite
done
microk8s helm upgrade --install kong kong/kong \
  --skip-crds \
  --set replicaCount=1 \
  --set ingressController.enabled=true \
  --set ingressController.env.KONGHQ_COM_GLOBAL_PLUGINS=true \
  --set image.repository="${IMAGE_NAME}" \
  --set image.tag="${IMAGE_TAG}" \
  --set proxy.type=LoadBalancer \
  --set admin.enabled=true \
  --set admin.http.enabled=true \
  --set env.database=postgres \
  --set env.pg_host=${PG_HOST} \
  --set env.pg_user=kong \
  --set env.pg_password=kong \
  --set env.pg_database=kong \
  --set env.redis_host=redis-master.default.svc.cluster.local \
  --set env.redis_port=6379 \
  --set-string env.plugins="bundled\,oidcify\,cors\,rate-limiting\,ip-restriction" \
  --set env.pluginserver_names=oidcify \
  --set env.pluginserver_oidcify_start_cmd="/usr/local/bin/oidcify -kong-prefix /kong_prefix" \
  --set env.pluginserver_oidcify_query_cmd="/usr/local/bin/oidcify -dump" \
  --set proxy.trusted_ips="{103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,104.16.0.0/13,104.24.0.0/14,108.162.192.0/18,131.0.72.0/22,141.101.64.0/18,162.158.0.0/15,172.64.0.0/13,173.245.48.0/20,188.114.96.0/20,190.93.240.0/20,197.234.240.0/22,198.41.128.0/17}" \
  --set proxy.real_ip_header="X-Forwarded-For" \
  --set proxy.real_ip_recursive=true \
  --set env.KONG_TRUSTED_IPS="0.0.0.0/0\,::/0" \
  --set env.KONG_REAL_IP_HEADER="X-Forwarded-For" \
  --set env.KONG_REAL_IP_RECURSIVE="on" \
  --set env.KONG_HEADERS_UPSTREAM="X-Forwarded-Proto:https"
kubectl -n default rollout status deployment/kong-kong --timeout=600s
kubectl create secret tls cloudflare-origin-cert --cert=../../.origin.crt --key=../../.origin.key -n default
