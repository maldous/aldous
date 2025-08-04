#!/usr/bin/env bash
set -euo pipefail

if systemctl is-active --quiet snap.microk8s.daemon-apiserver; then
  microk8s stop
  mount | awk '/microk8s\/common/ {print $3}' | \
    xargs -r -n1 sudo umount
  ip netns list | awk '{print $1}' | \
    xargs -r -n1 sudo ip netns delete
fi

snap remove microk8s --purge || true
snap remove microceph --purge || true

snap install microk8s --classic
microk8s status --wait-ready

mkdir -p ~/.kube
microk8s config > ~/.kube/config

microk8s enable community
microk8s enable rook-ceph

microk8s kubectl -n rook-ceph wait --for=condition=Ready pods --all --timeout=600s

snap install microceph
modprobe ceph
microceph cluster bootstrap
microceph disk add loop,512G,1
ceph config set mon mon_allow_pool_size_one true
ceph config set global osd_pool_default_size 1
ceph config set global osd_pool_default_min_size 1
ceph osd pool create microk8s-rbd0 32
ceph osd pool application enable microk8s-rbd0 rbd
ceph osd pool set microk8s-rbd0 size 1 --yes-i-really-mean-it
ceph osd pool set microk8s-rbd0 min_size 1 --yes-i-really-mean-it
ceph osd pool create microk8s-cephfs-meta 32
ceph osd pool application enable microk8s-cephfs-meta cephfs
ceph osd pool set microk8s-cephfs-meta size 1 --yes-i-really-mean-it
ceph osd pool set microk8s-cephfs-meta min_size 1 --yes-i-really-mean-it
ceph osd pool create microk8s-cephfs-data 64
ceph osd pool application enable microk8s-cephfs-data cephfs
ceph osd pool set microk8s-cephfs-data size 1 --yes-i-really-mean-it
ceph osd pool set microk8s-cephfs-data min_size 1 --yes-i-really-mean-it
ceph fs new microk8sfs microk8s-cephfs-meta microk8s-cephfs-data

CONF=$(find /var/snap/microceph -name ceph.conf | head -n1)
KEYRING=$(find /var/snap/microceph -name ceph.client.admin.keyring | head -n1)
microk8s connect-external-ceph \
  --ceph-conf "$CONF" \
  --keyring "$KEYRING" \
  --rbd-pool microk8s-rbd0

microk8s kubectl -n rook-ceph wait \
  --for=condition=Ready pods \
  --all \
  --timeout=600s

microk8s enable registry --storageclass cephfs

microk8s kubectl patch storageclass ceph-rbd \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

microk8s kubectl -n container-registry rollout status \
  deployment/registry --timeout=600s

microk8s enable minio -s ceph-rbd -c 20Gi

microk8s kubectl -n minio-operator rollout status deployment/minio-operator --timeout=600s

microk8s enable cloudnative-pg

microk8s kubectl -n cnpg-system wait --for=condition=Ready pods --all --timeout=600s

microk8s kubectl delete sc microk8s-hostpath

cat <<'EOF' | microk8s kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-cluster
  namespace: default
spec:
  instances: 1
  storage:
    size: 10Gi
    storageClass: ceph-rbd
EOF

microk8s kubectl -n default wait cluster/pg-cluster --for=condition=Ready --timeout=600s

PG_POD=$(microk8s kubectl -n default get pods -l cnpg.io/cluster=pg-cluster -o jsonpath='{.items[0].metadata.name}')
PG_HOST=pg-cluster-rw.default.svc.cluster.local

microk8s kubectl -n default exec -i "$PG_POD" -- psql -U postgres <<'EOF'
CREATE ROLE aldous LOGIN PASSWORD 'aldous';
CREATE DATABASE aldous OWNER aldous ENCODING 'UTF8';
CREATE ROLE keycloak LOGIN PASSWORD 'keycloak';
CREATE DATABASE keycloak OWNER keycloak ENCODING 'UTF8';
CREATE ROLE kong LOGIN PASSWORD 'kong';
CREATE DATABASE kong OWNER kong ENCODING 'UTF8';
EOF

microk8s kubectl -n default create secret generic aldous-pg \
  --dry-run=client -o yaml \
  --from-literal=username=aldous \
  --from-literal=password=aldous \
  --from-literal=database=aldous | microk8s kubectl apply -f -
microk8s kubectl -n default create secret generic keycloak-pg \
  --dry-run=client -o yaml \
  --from-literal=username=keycloak \
  --from-literal=password=keycloak \
  --from-literal=database=keycloak | microk8s kubectl apply -f -

microk8s helm repo add bitnami https://charts.bitnami.com/bitnami
microk8s helm repo update
microk8s helm install memcached bitnami/memcached 
microk8s helm upgrade --install redis bitnami/redis \
  --set architecture=standalone \
  --set auth.enabled=false \
  --set master.persistence.storageClass=ceph-rbd \
  --set master.persistence.size=3Gi

MINIO_HOST=microk8s-hl.minio-operator.svc.cluster.local
MINIO_ACCESS=$(microk8s kubectl -n minio-operator get secret microk8s-user-1 -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
MINIO_SECRET=$(microk8s kubectl -n minio-operator get secret microk8s-user-1 -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)
microk8s kubectl run mc-bucket --image=minio/mc --restart=Never --rm -it \
  --env "MC_HOST_local=http://${MINIO_ACCESS}:${MINIO_SECRET}@${MINIO_HOST}:9000" \
  --command -- mc mb local/keycloak-bucket --ignore-existing
microk8s kubectl run mc-bucket --image=minio/mc --restart=Never --rm -it \
  --env "MC_HOST_local=http://${MINIO_ACCESS}:${MINIO_SECRET}@${MINIO_HOST}:9000" \
  --command -- mc mb local/aldous-bucket --ignore-existing

METALLB_RANGE="192.168.1.240-192.168.1.250"
microk8s enable metallb:${METALLB_RANGE}

IMAGE_NAME="localhost:32000/kong-oidc"
IMAGE_TAG="3.7.0"
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile.kong .
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
  --set-string env.plugins="bundled\,oidcify\,cors\,rate-limiting\,ip-restriction\,jwt-claims-headers" \
  --set env.pluginserver_names=oidcify \
  --set env.pluginserver_oidcify_start_cmd="/usr/local/bin/oidcify -kong-prefix /kong_prefix" \
  --set env.pluginserver_oidcify_query_cmd="/usr/local/bin/oidcify -dump"

microk8s kubectl -n default rollout status deployment/kong-kong --timeout=600s

microk8s enable cert-manager
microk8s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=600s
microk8s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cainjector -n cert-manager --timeout=600s
microk8s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=webhook -n cert-manager --timeout=600s

cat <<'EOF' | microk8s kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token-secret
  namespace: cert-manager
type: Opaque
stringData:
  api-token: He7sJey3TBY-LqP5kB5i7dGt-bTSVFElAjxNL_a5
EOF

cat <<'EOF' | microk8s kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: admin@aldous.info
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
    - selector:
        dnsZones:
        - "aldous.info"
      dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token-secret
            key: api-token
EOF

cat <<'EOF' | microk8s kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: aldous-tls
  namespace: default
spec:
  secretName: aldous-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
  - "aldous.info"
  - "*.aldous.info"
EOF

microk8s kubectl wait certificate aldous-tls -n default --for=condition=Ready --timeout=600s

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

microk8s kubectl -n default wait --for=condition=Ready pod/keycloak-0 --timeout=600s

cat <<'EOF' | microk8s kubectl apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: oidc-user
username: oidc-user
EOF

microk8s kubectl exec -i keycloak-0 -- bash <<'EOF'
CONFIG=/tmp/kcadm.config
REALM=aldous
CLIENT_ID=kong
CLIENT_SECRET=kong-secret

/opt/bitnami/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password changeme \
  --config "$CONFIG"

/opt/bitnami/keycloak/bin/kcadm.sh create realms --config "$CONFIG" \
  -s realm="$REALM" \
  -s enabled=true \
  -s registrationAllowed=true \
  -s sslRequired=external \
  -s displayName="$REALM"

/opt/bitnami/keycloak/bin/kcadm.sh create clients -r "$REALM" --config "$CONFIG" \
  -s clientId="$CLIENT_ID" \
  -s "redirectUris=[\"https://aldous.info/callback\"]" \
  -s "webOrigins=[\"https://aldous.info\"]" \
  -s publicClient=false \
  -s protocol=openid-connect \
  -s clientAuthenticatorType=client-secret \
  -s secret="$CLIENT_SECRET" \
  -s 'attributes."access.token.lifespan"=300' \
  -s 'attributes."sso.session.idle.timeout"=1800' \
  -s 'attributes."sso.session.max.lifespan"=36000'

CLIENT_UUID=$(/opt/bitnami/keycloak/bin/kcadm.sh get clients -r "$REALM" --config "$CONFIG" -q clientId="$CLIENT_ID" --fields id --format csv --noquotes | tail -n1)

/opt/bitnami/keycloak/bin/kcadm.sh create clients/$CLIENT_UUID/protocol-mappers/models -r "$REALM" --config "$CONFIG" -f - <<JSON
{
  "name": "email",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-property-mapper",
  "consentRequired": false,
  "config": {
    "userinfo.token.claim": "true",
    "user.attribute": "email",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "claim.name": "email",
    "jsonType.label": "String"
  }
}
JSON

/opt/bitnami/keycloak/bin/kcadm.sh create clients/$CLIENT_UUID/protocol-mappers/models -r "$REALM" --config "$CONFIG" -f - <<JSON
{
  "name": "preferred_username",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-property-mapper",
  "consentRequired": false,
  "config": {
    "userinfo.token.claim": "true",
    "user.attribute": "username",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "claim.name": "preferred_username",
    "jsonType.label": "String"
  }
}
JSON
EOF

cat <<'EOF' | microk8s kubectl apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: oidc-protection
plugin: oidcify
config:
  issuer: "https://auth.aldous.info/realms/aldous"
  client_id: kong
  client_secret: kong-secret
  redirect_uri: "https://aldous.info/callback"
  insecure_skip_verify: true
  consumer_name: oidc-user
  id_token_claims_header: X-ID-Token-Claims
  userinfo_claims_header: X-Userinfo-Claims
  use_userinfo: true
---
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: jwt-claims-to-headers
plugin: jwt-claims-headers
config:
  uri_param_names:
    - jwt
EOF
