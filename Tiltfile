# Tilt-native configuration using static manifests
# To regenerate static manifests: make generate-manifests

commit_sha = str(local('git rev-parse --short HEAD')).strip()

images = {
    "kong": { "name": "localhost:5000/kong-oidc", "tag": "3.11-ubuntu" },
    "aldous": { "name": "localhost:5000/aldous", "tag": commit_sha }
}

# Deploy infrastructure first
k8s_yaml('k8s/cloudnative-pg.yaml')
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

# Deploy PostgreSQL cluster
k8s_yaml('k8s/pg-cluster.yaml')

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
k8s_resource('cnpg-controller-manager', new_name='cnpg-operator')
k8s_resource('redis-master', resource_deps=['cnpg-operator'])
k8s_resource('memcached', resource_deps=['cnpg-operator'])
k8s_resource('minio', resource_deps=['cnpg-operator'])
k8s_resource('keycloak', resource_deps=['minio', 'cnpg-operator'])
k8s_resource('kong-kong', new_name='kong', resource_deps=['cnpg-operator'])
k8s_resource('aldous', resource_deps=['kong'], port_forwards=['8000:80'])
k8s_resource('keycloak-setup', resource_deps=['keycloak'])

# Configure image substitution
k8s_image_json_path('{.spec.template.spec.containers[0].image}', images['aldous']['name'] + ':latest', images['aldous']['name'] + ':' + images['aldous']['tag'])
