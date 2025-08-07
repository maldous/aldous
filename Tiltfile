load('ext://helm_remote', 'helm_remote')

config.define_string('registry_port')
config.define_string('pg_host')
config.define_string('minio_host')
config.define_string('kong_image_tag')
config.define_string('aldous_image_tag')

cfg = config.parse()

# Get git commit SHA for image tagging
commit_sha = str(local('git rev-parse --short HEAD')).strip()

# Central image map - using localhost:5000 for Kind registry
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

# Build images with live updates - moved after registry setup
# Images will be built by Tilt automatically when registry is ready

# Kubernetes manifests
k8s_yaml([
    'k8s/aldous-deployment.yaml',
    'k8s/aldous-service.yaml', 
    'k8s/aldous-ingress.yaml',
    'k8s/pg-cluster.yaml',

    'k8s/minio-secret.yaml',
    'k8s/oidc-protection.yaml',
    'k8s/oidc-user.yaml',
    'k8s/cloudflare-origin-cert-secret.yaml',
])

# Infrastructure setup for Kind
local_resource(
  'kind_cluster',
  cmd='kind create cluster --config kind-config.yaml --wait 5m || true',
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'registry_setup',
  cmd='docker rm -f kind-registry 2>/dev/null || true && docker run -d --restart=always --name kind-registry --network kind registry:2 && until docker exec aldous-control-plane curl -f http://kind-registry:5000/v2/ 2>/dev/null; do echo "Waiting for registry..."; sleep 2; done',
  resource_deps=['kind_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'metallb_setup',
  cmd='kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml && kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s',
  resource_deps=['kind_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'metallb_config',
  cmd='kubectl apply -f - <<EOF\napiVersion: metallb.io/v1beta1\nkind: IPAddressPool\nmetadata:\n  name: example\n  namespace: metallb-system\nspec:\n  addresses:\n  - 192.168.1.240-192.168.1.250\n---\napiVersion: metallb.io/v1beta1\nkind: L2Advertisement\nmetadata:\n  name: empty\n  namespace: metallb-system\nEOF',
  resource_deps=['metallb_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'cloudnative_pg',
  cmd='kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.20/releases/cnpg-1.20.0.yaml && kubectl wait --namespace cnpg-system --for=condition=ready pod --selector=app.kubernetes.io/name=cloudnative-pg --timeout=300s',
  resource_deps=['kind_cluster'],
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
  resource_deps=['kind_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'oidc_client_secret',
  cmd='kubectl get secret oidc-client-secret >/dev/null 2>&1 || kubectl create secret generic oidc-client-secret --from-literal=client-secret=$(openssl rand -base64 32)',
  resource_deps=['kind_cluster'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

# Build images after registry is ready
local_resource(
  'build_images',
  cmd='docker build -t ' + images['kong']['name'] + ':' + images['kong']['tag'] + ' -f docker/Dockerfile.kong . && kind load docker-image ' + images['kong']['name'] + ':' + images['kong']['tag'] + ' --name aldous && docker build -t ' + images['aldous']['name'] + ':' + images['aldous']['tag'] + ' -f docker/Dockerfile.aldous . && kind load docker-image ' + images['aldous']['name'] + ':' + images['aldous']['tag'] + ' --name aldous',
  resource_deps=['registry_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

# Note: docker_build calls moved to local_resource to ensure proper dependency ordering

# Helm deployments with explicit triggers
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
  resource_deps=['postgres_cluster', 'metallb_config', 'build_images', 'oidc_client_secret'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'deploy_keycloak',
  cmd='helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update && helm upgrade --install keycloak bitnami/keycloak -f helm/keycloak-values.yaml --set externalDatabase.host=' + env['PG_HOST'] + ' --set extraEnv[1].value=http://' + env['MINIO_HOST'] + ':9000',
  resource_deps=['deploy_minio', 'keycloak_admin_secret'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

# Aldous k8s resource with port forwarding
k8s_resource('aldous', port_forwards=['8000:80'], resource_deps=['build_images', 'deploy_kong'])

# Ingress check - manual trigger only
local_resource(
    'ingress_check',
    cmd='bash -c "until curl -sf http://localhost:80/; do sleep 5; done && echo ingress OK"',
    resource_deps=['aldous'],
    trigger_mode=TRIGGER_MODE_MANUAL,
)
