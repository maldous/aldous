commit_sha = str(local('git rev-parse --short HEAD')).strip()
images = {
    "kong": { "name": "localhost:5000/kong-oidc", "tag": "3.11-ubuntu" },
    "aldous": { "name": "localhost:5000/aldous", "tag": commit_sha }
}

k8s_yaml('k8s/obs-ns.yaml')
k8s_yaml('k8s/generated/cloudnative-pg-operator.yaml')
k8s_yaml('k8s/generated/redis.yaml')
k8s_yaml('k8s/generated/memcached.yaml')
k8s_yaml('k8s/generated/minio.yaml')
k8s_yaml(['k8s/pod-security-policy.yaml', 'k8s/security-policies.yaml', 'k8s/aldous-rbac.yaml', 'k8s/aldous-secrets.yaml'])
k8s_yaml('k8s/generated/keycloak.yaml')
k8s_yaml('k8s/generated/kong.yaml')
k8s_yaml(['k8s/aldous-deployment.yaml', 'k8s/aldous-service.yaml', 'k8s/aldous-ingress.yaml', 'k8s/aldous-networkpolicy.yaml', 'k8s/aldous-pdb.yaml'])
k8s_yaml(['k8s/oidc-protection.yaml', 'k8s/oidc-user.yaml'])
k8s_yaml('k8s/keycloak-setup-job.yaml')

k8s_yaml('k8s/generated/loki.yaml')
k8s_yaml('k8s/generated/tempo.yaml')
k8s_yaml('k8s/generated/prometheus.yaml')
k8s_yaml('k8s/generated/grafana.yaml')
k8s_yaml('k8s/generated/alloy.yaml')
k8s_yaml('k8s/generated/mailhog.yaml')
k8s_yaml('k8s/generated/meilisearch.yaml')

k8s_yaml(['k8s/queue-worker.yaml', 'k8s/horizon.yaml'])

watch_settings(ignore=['.git/', 'vendor/', '.tilt/'])

docker_build(images['kong']['name'] + ':' + images['kong']['tag'], '.', dockerfile='docker/Dockerfile.kong')
docker_build(images['aldous']['name'] + ':latest', '.', dockerfile='docker/Dockerfile.aldous', 
  live_update=[
    sync('./artisan', '/var/www/html/artisan'),
    sync('./app', '/var/www/html/app'),
    sync('./bootstrap', '/var/www/html/bootstrap'),
    sync('./config', '/var/www/html/config'),
    sync('./routes', '/var/www/html/routes'),
    sync('./resources', '/var/www/html/resources'),
    sync('./public', '/var/www/html/public'),
    sync('./composer.json', '/var/www/html/composer.json'),
    sync('./composer.lock', '/var/www/html/composer.lock'),
],)

local_resource('kong-crds',
    cmd='kubectl apply -f k8s/kong-crds.yaml && kubectl wait --for=condition=Established --timeout=120s crd/kongplugins.configuration.konghq.com crd/kongclusterplugins.configuration.konghq.com crd/kongconsumers.configuration.konghq.com crd/kongingresses.configuration.konghq.com',
    deps=['k8s/kong-crds.yaml']
)

k8s_resource('cnpg-operator-cloudnative-pg')

local_resource('wait-cnpg-webhook',
    cmd='kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cloudnative-pg --timeout=600s && kubectl get service cnpg-webhook-service && sleep 5',
    resource_deps=['cnpg-operator-cloudnative-pg']
)

local_resource('deploy-pg-cluster',
    cmd='kubectl apply -f k8s/generated/pg-cluster.yaml && kubectl wait --for=condition=Ready cluster/pg-cluster --timeout=600s',
    resource_deps=['wait-cnpg-webhook']
)

k8s_resource('redis-master')
k8s_resource('memcached')
k8s_resource('minio')
k8s_resource('keycloak', resource_deps=['deploy-pg-cluster', 'minio', 'redis-master'])
k8s_resource('kong-kong-init-migrations', resource_deps=['deploy-pg-cluster', 'kong-crds'])
k8s_resource('kong-kong-pre-upgrade-migrations', resource_deps=['kong-kong-init-migrations'])
k8s_resource('kong-kong-post-upgrade-migrations', resource_deps=['kong-kong-pre-upgrade-migrations'])
k8s_resource('kong-kong', resource_deps=['kong-kong-post-upgrade-migrations', 'kong-crds'])
k8s_resource('loki')
k8s_resource('tempo')
k8s_resource('prometheus-server', new_name='prometheus')
k8s_resource('prometheus-kube-state-metrics')
k8s_resource('prometheus-prometheus-node-exporter', new_name='node-exporter')
k8s_resource('grafana', resource_deps=['loki','tempo','prometheus'])
k8s_resource('alloy')
k8s_resource('mailhog')
k8s_resource('meilisearch')
k8s_resource('aldous', resource_deps=['kong-kong'], port_forwards=['8000:8000'], extra_pod_selectors=[{'app': 'aldous'}])
k8s_resource('keycloak-setup', resource_deps=['keycloak'])
k8s_resource('app-queue', resource_deps=['redis-master', 'aldous'])
k8s_resource('app-horizon', resource_deps=['redis-master', 'aldous'])

k8s_image_json_path(
    '{.spec.template.spec.containers[0].image}',
    images['aldous']['name'] + ':latest',
    images['aldous']['name'] + ':' + images['aldous']['tag']
)

local_resource('k8s-inspect',
    cmd="""
set -e
kubectl get secrets -A -o json | jq -r -f /dev/fd/3 3<<'JQ'
.items[]
| select(.type!="kubernetes.io/service-account-token")
| select( (.data // {}) as $d
| ( ($d | keys | map(test("(^|[.])tls[.]crt$|(^|[.])tls[.]key$|[.]crt$|[.]key$|(^|[^A-Za-z])cert([^A-Za-z]|$)|certificate|ca[.]crt$|ca[.]key$"; "i")) | index(true)) == null) and ( ($d | to_entries | map((.value | @base64d) | test("^-----BEGIN [A-Z ]+-----"; "m")) | index(true)) == null))
| {ns:.metadata.namespace, name:.metadata.name, values:(.data // {} | with_entries(.value = ((.value|@base64d)|tostring)))}
JQ
""",
    trigger_mode=TRIGGER_MODE_MANUAL,
)
