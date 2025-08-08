load('ext://helm_remote', 'helm_remote')

config.define_string('registry_port')
config.define_string('pg_host')
config.define_string('minio_host')
config.define_string('kong_image_tag')
config.define_string('aldous_image_tag')
cfg = config.parse()

commit_sha = str(local('git rev-parse --short HEAD')).strip()
network_iface = str(local("ip -o -4 route show to default | grep -v docker | head -1 | awk '{print $5}'")).strip()
host_ip = str(local("ip -4 addr show " + network_iface + " | grep inet | grep -v 127 | head -1 | awk '{print $2}' | cut -d/ -f1")).strip()
metallb_ip = host_ip
metallb_range = host_ip + '-' + host_ip

images = {
    "kong": {
        "name": "localhost:5000/kong-oidc",
        "tag": cfg.get("kong_image_tag") or "3.11-ubuntu"
    },
    "aldous": {
        "name": "localhost:5000/aldous",
        "tag": cfg.get("aldous_image_tag") or "latest"
    }
}

env = {
    "REGISTRY_PORT": cfg.get("registry_port") or "5000",
    "PG_HOST":       cfg.get("pg_host")       or "pg-cluster-rw.default.svc.cluster.local",
    "MINIO_HOST":    cfg.get("minio_host")    or "minio.default.svc.cluster.local",
}

k8s_yaml([
    'k8s/aldous-deployment.yaml',
    'k8s/aldous-service.yaml',
    'k8s/aldous-ingress.yaml',
    'k8s/pg-cluster.yaml',
    'k8s/oidc-protection.yaml',
    'k8s/oidc-user.yaml',
    'k8s/cloudflare-origin-cert-secret.yaml',
])

local_resource(
  'registry_setup',
  cmd='docker rm -f kind-registry 2>/dev/null || true && docker run -d --restart=always --name kind-registry --network kind registry:2 && until docker exec aldous-control-plane curl -f http://kind-registry:5000/v2/ 2>/dev/null; do echo "Waiting for registry..."; sleep 2; done',
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'metallb_setup',
  cmd='kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml && kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s',
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'metallb_network_setup',
  cmd='sudo ip addr add ' + metallb_ip + '/32 dev ' + network_iface + ' || true && kubectl apply -f - <<EOF\napiVersion: metallb.io/v1beta1\nkind: IPAddressPool\nmetadata:\n  name: example\n  namespace: metallb-system\nspec:\n  addresses:\n  - ' + metallb_range + '\n---\napiVersion: metallb.io/v1beta1\nkind: L2Advertisement\nmetadata:\n  name: empty\n  namespace: metallb-system\nEOF',
  resource_deps=['metallb_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'cloudnative_pg',
  cmd='kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.20/releases/cnpg-1.20.0.yaml && kubectl wait --namespace cnpg-system --for=condition=ready pod --selector=app.kubernetes.io/name=cloudnative-pg --timeout=300s',
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'postgres_cluster',
  cmd='kubectl apply -f k8s/pg-cluster.yaml && kubectl wait --for=condition=ready cluster/pg-cluster --timeout=300s',
  resource_deps=['cloudnative_pg'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'keycloak_admin_secret',
  cmd='kubectl get secret keycloak-admin >/dev/null 2>&1 || kubectl create secret generic keycloak-admin --from-literal=admin-password=$(openssl rand -base64 32)',
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'oidc_client_secret',
  cmd='kubectl get secret oidc-client-secret >/dev/null 2>&1 || kubectl create secret generic oidc-client-secret --from-literal=client-secret=$(openssl rand -base64 32)',
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'minio_secret',
  cmd='kubectl get secret minio-root-credentials >/dev/null 2>&1 || kubectl create secret generic minio-root-credentials --from-literal=root-user=minioadmin --from-literal=root-password=$(openssl rand -base64 32)',
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'build_images',
  cmd='docker build -t ' + images['kong']['name'] + ':' + images['kong']['tag'] + ' -f docker/Dockerfile.kong . && kind load docker-image ' + images['kong']['name'] + ':' + images['kong']['tag'] + ' --name aldous && docker build -t ' + images['aldous']['name'] + ':' + images['aldous']['tag'] + ' -f docker/Dockerfile.aldous . && kind load docker-image ' + images['aldous']['name'] + ':' + images['aldous']['tag'] + ' --name aldous',
  resource_deps=['registry_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'deploy_minio',
  cmd='helm repo add minio https://charts.min.io/ && helm repo update && helm upgrade --install minio minio/minio -f helm/minio-values.yaml',
  resource_deps=['postgres_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'deploy_redis',
  cmd='helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update && helm upgrade --install redis bitnami/redis -f helm/redis-values.yaml',
  resource_deps=['postgres_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'deploy_memcached',
  cmd='helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update && helm upgrade --install memcached bitnami/memcached -f helm/memcached-values.yaml',
  resource_deps=['postgres_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'deploy_kong',
  cmd='helm repo add kong https://charts.konghq.com && helm repo update && helm upgrade --install kong kong/kong -f helm/kong-values.yaml --set image.repository=' + images['kong']['name'] + ' --set image.tag=' + images['kong']['tag'] + ' --set env.pg_host=' + env['PG_HOST'] + ' --set env.pg_database=app',
  resource_deps=['postgres_cluster', 'metallb_network_setup', 'build_images', 'oidc_client_secret'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'deploy_keycloak',
  cmd='helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update && helm upgrade --install keycloak bitnami/keycloak -f helm/keycloak-values.yaml --set externalDatabase.host=' + env['PG_HOST'] + ' --set extraEnv[1].value=http://' + env['MINIO_HOST'] + ':9000',
  resource_deps=['deploy_minio', 'keycloak_admin_secret', 'minio_secret'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
    'keycloak_realm_setup',
    cmd = """
kubectl wait --for=condition=ready pod/keycloak-0 --timeout=300s
CLIENT_SECRET=$(kubectl get secret oidc-client-secret -o jsonpath='{.data.client-secret}' | base64 -d)
ADMIN_PASSWORD=$(kubectl get secret keycloak-admin -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl exec -i keycloak-0 -- env CLIENT_SECRET="$CLIENT_SECRET" ADMIN_PASSWORD="$ADMIN_PASSWORD" bash <<'EOF'
CONFIG=/tmp/kcadm.config
REALM=aldous
CLIENT_ID=kong
/opt/bitnami/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password "$ADMIN_PASSWORD" \
  --config "$CONFIG"
/opt/bitnami/keycloak/bin/kcadm.sh create realms --config "$CONFIG" \
  -s realm="$REALM" \
  -s enabled=true \
  -s registrationAllowed=true \
  -s sslRequired=external \
  -s displayName="$REALM"
# Delete existing client if it exists
/opt/bitnami/keycloak/bin/kcadm.sh delete clients -r "$REALM" --config "$CONFIG" -q clientId="$CLIENT_ID" 2>/dev/null || true

/opt/bitnami/keycloak/bin/kcadm.sh create clients -r "$REALM" --config "$CONFIG" \
  -s clientId="$CLIENT_ID" \
  -s 'redirectUris=["https://aldous.info/callback"]' \
  -s 'webOrigins=["https://aldous.info"]' \
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
""",
    resource_deps=['deploy_keycloak', 'oidc_client_secret'],
    trigger_mode=TRIGGER_MODE_AUTO,
)

k8s_resource('aldous', port_forwards=['8000:80'], resource_deps=['build_images', 'deploy_kong'])
