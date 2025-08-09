load('ext://helm_remote', 'helm_remote')

commit_sha = str(local('git rev-parse --short HEAD')).strip()

images = {
    "kong": { "name": "localhost:5000/kong-oidc", "tag": "3.11-ubuntu" },
    "aldous": { "name": "localhost:5000/aldous", "tag": commit_sha }
}

k8s_yaml([ 'k8s/pod-security-policy.yaml', 'k8s/security-policies.yaml', 'k8s/aldous-rbac.yaml', 'k8s/aldous-secrets.yaml' ])
k8s_yaml([ 'k8s/aldous-deployment.yaml', 'k8s/aldous-service.yaml', 'k8s/aldous-ingress.yaml', 'k8s/aldous-networkpolicy.yaml', 'k8s/aldous-pdb.yaml', 'k8s/aldous-priority.yaml' ])
k8s_yaml([ 'k8s/pg-cluster.yaml', 'k8s/oidc-protection.yaml', 'k8s/oidc-user.yaml' ])

watch_settings(ignore=['.git/', 'vendor/'])

local_resource( 'build_kong',
  cmd="""
set -e
docker build -t localhost:5000/kong-oidc:3.11-ubuntu -f docker/Dockerfile.kong .
kind load docker-image localhost:5000/kong-oidc:3.11-ubuntu --name aldous
""",
  deps=['docker/Dockerfile.kong'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

custom_build(
  ref=images['aldous']['name'] + ':latest',
  command='docker build -t $EXPECTED_REF -f docker/Dockerfile.aldous . && kind load docker-image $EXPECTED_REF --name aldous',
  deps=['docker/Dockerfile.aldous', 'app'],
  live_update=[sync('./app', '/var/www/html')],
)

k8s_image_json_path('{.spec.template.spec.containers[0].image}', images['aldous']['name'] + ':latest', images['aldous']['name'] + ':' + images['aldous']['tag'])

local_resource(
  'cloudnative_pg',
  cmd='kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.20/releases/cnpg-1.20.0.yaml && ' + 'kubectl wait --namespace cnpg-system --for=condition=ready pod --selector=app.kubernetes.io/name=cloudnative-pg --timeout=300s',
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource( 'postgres_cluster',
  cmd='kubectl apply -f k8s/pg-cluster.yaml && kubectl wait --for=condition=ready cluster/pg-cluster --timeout=300s',
  resource_deps=['cloudnative_pg'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource( 'deploy_kong',
  cmd=r"""
set -e
CHKSUM=$(sha1sum helm/kong-values.yaml | cut -d' ' -f1)
STATE=.tilt/kong.$CHKSUM
mkdir -p .tilt
[ -f "$STATE" ] || {
  helm upgrade --install kong kong/kong \
    -f helm/kong-values.yaml \
    --set image.repository=localhost:5000/kong-oidc \
    --set image.tag=3.11-ubuntu \
    --set image.pullPolicy=IfNotPresent \
    --history-max 2 --atomic --timeout 90s --reuse-values
  touch "$STATE"
}
""",
  deps=['helm/kong-values.yaml'],
  resource_deps=['postgres_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'deploy_minio',
  cmd='helm upgrade --install minio minio/minio -f helm/minio-values.yaml',
  resource_deps=['postgres_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'deploy_redis',
  cmd='helm upgrade --install redis bitnami/redis -f helm/redis-values.yaml',
  resource_deps=['postgres_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'deploy_memcached',
  cmd='helm upgrade --install memcached bitnami/memcached -f helm/memcached-values.yaml',
  resource_deps=['postgres_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'deploy_keycloak',
  cmd='helm upgrade --install keycloak bitnami/keycloak -f helm/keycloak-values.yaml',
  resource_deps=['deploy_minio'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
    'keycloak_realm_setup',
    cmd = """
set -e
kubectl wait --for=condition=ready pod/keycloak-0 --timeout=300s
ADMIN_PASSWORD=$(kubectl get secret keycloak-admin -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl exec -i keycloak-0 -- env ADMIN_PASSWORD="$ADMIN_PASSWORD" bash <<'EOF'
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
/opt/bitnami/keycloak/bin/kcadm.sh create clients -r "$REALM" --config "$CONFIG" \
  -s clientId="$CLIENT_ID" \
  -s 'redirectUris=["https://aldous.info/callback"]' \
  -s 'webOrigins=["https://aldous.info"]' \
  -s publicClient=false \
  -s protocol=openid-connect \
  -s clientAuthenticatorType=client-secret \
  -s secret=secret \
  -s serviceAccountsEnabled=true \
  -s standardFlowEnabled=true \
  -s directAccessGrantsEnabled=true \
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
    resource_deps=['deploy_keycloak'],
    trigger_mode=TRIGGER_MODE_AUTO,
)
