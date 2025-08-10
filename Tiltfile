commit_sha = str(local('git rev-parse --short HEAD')).strip()
images = {
    "kong": { "name": "localhost:5000/kong-oidc", "tag": "3.11-ubuntu" },
    "aldous": { "name": "localhost:5000/aldous", "tag": commit_sha }
}

# --- core infra
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

local_resource(
  'apply-monitoring-crds',
  cmd='kubectl apply --server-side --field-manager=tilt-crds --force-conflicts -f k8s/prometheus-crds.yaml',
  deps=['k8s/prometheus-crds.yaml'],
)

# wait until CRDs are Established to avoid "no matches for kind Alertmanager"
local_resource(
    'wait-monitoring-crds',
    cmd="""
set -e
for crd in \
  alertmanagers.monitoring.coreos.com \
  alertmanagerconfigs.monitoring.coreos.com \
  podmonitors.monitoring.coreos.com \
  probes.monitoring.coreos.com \
  prometheuses.monitoring.coreos.com \
  prometheusrules.monitoring.coreos.com \
  scrapeconfigs.monitoring.coreos.com \
  servicemonitors.monitoring.coreos.com \
  thanosrulers.monitoring.coreos.com
do
  kubectl wait --for=condition=Established --timeout=180s crd/$crd
done
""",
)

# kube-prometheus-stack (rendered with --include-crds, safe because CRDs are already applied)
k8s_yaml('k8s/generated/prom-stack.yaml')
local_resource( 'wait-prom-admission-secret',
  cmd='''bash -eu
for i in {1..90}; do
  if kubectl -n observability get secret prom-stack-admission >/dev/null 2>&1; then
    exit 0
  fi
  sleep 2
done
echo "timeout waiting for secret/prom-stack-admission" >&2
exit 1
''',
  resource_deps=['wait-monitoring-crds'],
)
k8s_resource('prom-stack-operator', resource_deps=['wait-prom-admission-secret'])

# --- obs/tools
k8s_yaml('k8s/generated/loki.yaml')
k8s_yaml('k8s/generated/tempo.yaml')
k8s_yaml('k8s/generated/grafana.yaml')
k8s_yaml('k8s/generated/alloy.yaml')
k8s_yaml('k8s/generated/mailhog.yaml')
k8s_yaml('k8s/generated/meilisearch.yaml')

# --- app workers
k8s_yaml(['k8s/queue-worker.yaml', 'k8s/horizon.yaml'])

watch_settings(ignore=['.git/', 'vendor/', '.tilt/'])

docker_build(images['kong']['name'] + ':' + images['kong']['tag'], '.', dockerfile='docker/Dockerfile.kong')
docker_build(images['aldous']['name'] + ':latest', '.', dockerfile='docker/Dockerfile.aldous', live_update=[ sync('./app', '/var/www/html') ])

local_resource('kong-crds',
    cmd='kubectl apply -f k8s/kong-crds.yaml && kubectl wait --for=condition=Established --timeout=120s crd/kongplugins.configuration.konghq.com crd/kongclusterplugins.configuration.konghq.com crd/kongconsumers.configuration.konghq.com crd/kongingresses.configuration.konghq.com',
    deps=['k8s/kong-crds.yaml']
)

k8s_resource('cnpg-operator-cloudnative-pg')

local_resource('wait-cnpg-webhook',
    cmd='kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cloudnative-pg --timeout=300s && kubectl get service cnpg-webhook-service && sleep 5',
    resource_deps=['cnpg-operator-cloudnative-pg']
)

local_resource('deploy-pg-cluster',
    cmd='kubectl apply -f k8s/generated/pg-cluster.yaml && kubectl wait --for=condition=Ready cluster/pg-cluster --timeout=300s',
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

k8s_resource('prom-stack-operator', resource_deps=['wait-monitoring-crds'])
k8s_resource('prom-stack-kube-state-metrics', resource_deps=['wait-monitoring-crds'])
k8s_resource('prom-stack-prometheus-node-exporter', resource_deps=['wait-monitoring-crds'])

k8s_resource('loki')
k8s_resource('tempo')
k8s_resource('grafana', resource_deps=['loki','tempo'])
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
