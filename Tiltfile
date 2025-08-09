# Tilt-native configuration using static manifests
# To regenerate static manifests: make generate-manifests

commit_sha = str(local('git rev-parse --short HEAD')).strip()

images = {
    "kong": { "name": "localhost:5000/kong-oidc", "tag": "3.11-ubuntu" },
    "aldous": { "name": "localhost:5000/aldous", "tag": commit_sha }
}

# Deploy infrastructure first
k8s_yaml('k8s/generated/cloudnative-pg-operator.yaml')
k8s_yaml('k8s/kong-crds.yaml')
k8s_yaml('k8s/generated/redis.yaml')
k8s_yaml('k8s/generated/memcached.yaml')
k8s_yaml('k8s/generated/minio.yaml')

# Deploy security and RBAC
k8s_yaml([
    'k8s/pod-security-policy.yaml',
    'k8s/security-policies.yaml', 
    'k8s/aldous-rbac.yaml',
    'k8s/aldous-secrets.yaml'
])

# Deploy Keycloak
k8s_yaml('k8s/generated/keycloak.yaml')

# Deploy Kong
k8s_yaml('k8s/generated/kong.yaml')

# Deploy application
k8s_yaml([
    'k8s/aldous-deployment.yaml',
    'k8s/aldous-service.yaml', 
    'k8s/aldous-ingress.yaml',
    'k8s/aldous-networkpolicy.yaml',
    'k8s/aldous-pdb.yaml'
])

# Deploy OIDC configuration
k8s_yaml([
    'k8s/oidc-protection.yaml',
    'k8s/oidc-user.yaml'
])

# Deploy Keycloak setup job
k8s_yaml('k8s/keycloak-setup-job.yaml')

watch_settings(ignore=['.git/', 'vendor/', '.tilt/', 'k8s/generated/'])

# Build Kong image
docker_build(
    images['kong']['name'] + ':' + images['kong']['tag'],
    '.',
    dockerfile='docker/Dockerfile.kong'
)

# Build Aldous image with live updates
docker_build(
    images['aldous']['name'] + ':latest',
    '.',
    dockerfile='docker/Dockerfile.aldous',
    live_update=[
        sync('./app', '/var/www/html')
    ]
)

# Configure resource dependencies
k8s_resource('cnpg-operator-cloudnative-pg', new_name='cnpg-operator')

# Wait for CNPG webhook to be ready before creating cluster
local_resource(
    'wait-cnpg-webhook',
    cmd='kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cloudnative-pg --timeout=300s && kubectl get service cnpg-webhook-service && sleep 5',
    resource_deps=['cnpg-operator']
)

# Deploy PostgreSQL cluster after webhook is ready
local_resource(
    'deploy-pg-cluster',
    cmd='kubectl apply -f k8s/generated/pg-cluster.yaml && kubectl wait --for=condition=Ready cluster/pg-cluster --timeout=300s',
    resource_deps=['wait-cnpg-webhook']
)

# Infra services don't depend on Postgres
k8s_resource('redis-master')
k8s_resource('memcached')
k8s_resource('minio')
k8s_resource('minio-post-job', resource_deps=['minio'])

# Postgres cluster comes from 'deploy-pg-cluster' local_resource (already depends on CNPG webhook)
# Keycloak needs PG + MinIO (+ Redis if enabled)
k8s_resource('keycloak', resource_deps=['deploy-pg-cluster', 'minio', 'redis-master'])

# Kong DB migrations must run after PG is ready
k8s_resource('kong-kong-init-migrations', resource_deps=['deploy-pg-cluster'])
k8s_resource('kong-kong-pre-upgrade-migrations', resource_deps=['kong-kong-init-migrations'])

# Kong proxy should start after migrations complete
k8s_resource('kong-kong', new_name='kong', resource_deps=['kong-kong-init-migrations', 'kong-kong-pre-upgrade-migrations'])

# Post-upgrade migrations only after Kong is up (no cycle)
k8s_resource('kong-kong-post-upgrade-migrations', resource_deps=['kong'])

# App can come after Kong (for ingress availability)
k8s_resource('aldous', resource_deps=['kong'], port_forwards=['8000:80'])
k8s_resource('keycloak-setup', resource_deps=['keycloak'])

# Configure image substitution
k8s_image_json_path('{.spec.template.spec.containers[0].image}', images['aldous']['name'] + ':latest', images['aldous']['name'] + ':' + images['aldous']['tag'])
