commit_sha = str(local('git rev-parse --short HEAD')).strip()

images = {
    "kong": { "name": "localhost:5000/kong-oidc", "tag": "3.11-ubuntu" },
    "aldous": { "name": "localhost:5000/aldous", "tag": commit_sha }
}

k8s_yaml('k8s/generated/cloudnative-pg-operator.yaml')
k8s_yaml('k8s/generated/redis.yaml')
k8s_yaml('k8s/generated/memcached.yaml')
k8s_yaml('k8s/generated/minio.yaml')
k8s_yaml(['k8s/pod-security-policy.yaml', 'k8s/security-policies.yaml', 'k8s/aldous-rbac.yaml', 'k8s/aldous-secrets.yaml' ])
k8s_yaml('k8s/generated/keycloak.yaml')
k8s_yaml('k8s/generated/kong.yaml')
k8s_yaml(['k8s/aldous-deployment.yaml', 'k8s/aldous-service.yaml', 'k8s/aldous-ingress.yaml', 'k8s/aldous-networkpolicy.yaml', 'k8s/aldous-pdb.yaml' ])
k8s_yaml(['k8s/oidc-protection.yaml', 'k8s/oidc-user.yaml' ])
k8s_yaml('k8s/keycloak-setup-job.yaml')

watch_settings(ignore=['.git/', 'vendor/', '.tilt/', 'k8s/generated/'])

docker_build(images['kong']['name'] + ':' + images['kong']['tag'], '.', dockerfile='docker/Dockerfile.kong')
docker_build(images['aldous']['name'] + ':latest', '.', dockerfile='docker/Dockerfile.aldous', live_update=[ sync('./app', '/var/www/html') ])

local_resource(
    'kong-crds',
    cmd='kubectl apply -f k8s/kong-crds.yaml && kubectl wait --for=condition=Established --timeout=120s crd/kongplugins.configuration.konghq.com crd/kongclusterplugins.configuration.konghq.com crd/kongconsumers.configuration.konghq.com crd/kongingresses.configuration.konghq.com',
    deps=['k8s/kong-crds.yaml']
)

k8s_resource('cnpg-operator-cloudnative-pg')
local_resource(
    'wait-cnpg-webhook',
    cmd='kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cloudnative-pg --timeout=300s && kubectl get service cnpg-webhook-service && sleep 5',
    resource_deps=['cnpg-operator-cloudnative-pg']
)
local_resource(
    'deploy-pg-cluster',
    cmd='kubectl apply -f k8s/generated/pg-cluster.yaml && kubectl wait --for=condition=Ready cluster/pg-cluster --timeout=300s',
    resource_deps=['wait-cnpg-webhook']
)

k8s_resource('redis-master')
k8s_resource('memcached')
k8s_resource('minio')
k8s_resource('minio-post-job', resource_deps=['minio'])
k8s_resource('keycloak', resource_deps=['deploy-pg-cluster', 'minio', 'redis-master'])
k8s_resource('kong-kong-init-migrations', resource_deps=['deploy-pg-cluster', 'kong-crds'])
k8s_resource('kong-kong-pre-upgrade-migrations', resource_deps=['kong-kong-init-migrations'])
k8s_resource('kong-kong-post-upgrade-migrations', resource_deps=['kong-kong-pre-upgrade-migrations'])
k8s_resource('kong-kong', resource_deps=['kong-kong-post-upgrade-migrations', 'kong-crds'])
k8s_resource('aldous', resource_deps=['kong-kong'], port_forwards=['8000:8000'], extra_pod_selectors=[{'app': 'aldous'}])
k8s_resource('keycloak-setup', resource_deps=['keycloak'])

k8s_image_json_path(
    '{.spec.template.spec.containers[0].image}',
    images['aldous']['name'] + ':latest',
    images['aldous']['name'] + ':' + images['aldous']['tag']
)
