load('ext://git_resource', 'git_checkout')
load('ext://helm_remote', 'helm_remote')

config.define_string('metallb_range')
config.define_string('pg_host')
config.define_string('minio_host')
config.define_string('kong_image_tag')
config.define_string('aldous_image_tag')

cfg = config.parse()

# Get git commit SHA for image tagging
commit_sha = str(local('git rev-parse --short HEAD')).strip()

# Central image map
images = {
    "kong": {
        "name": "localhost:32000/kong-oidc",
        "tag": cfg.get("kong_image_tag") or "3.7.0"
    },
    "aldous": {
        "name": "localhost:32000/aldous", 
        "tag": cfg.get("aldous_image_tag") or "latest"
    }
}

env = {
    "METALLB_RANGE": cfg.get("metallb_range") or "192.168.1.240-192.168.1.250",
    "PG_HOST":       cfg.get("pg_host")       or "pg-cluster-rw.default.svc.cluster.local",
    "MINIO_HOST":    cfg.get("minio_host")    or "microk8s-hl.minio-operator.svc.cluster.local",
}

# Generic builder helper
def build_image(name, context, dockerfile, sync_paths, build_args=None):
    ref = images[name]['name'] + ':' + images[name]['tag']
    docker_build(ref,
        context=context,
        dockerfile=dockerfile,
        build_args=build_args or {},
        live_update=[sync(src, dst) for src, dst in sync_paths]
    )
    return ref

# Build images with improved caching and live updates
# Kong image build moved to after registry setup

aldous_ref = docker_build(
    images['aldous']['name'] + ':' + images['aldous']['tag'],
    context=".",
    dockerfile="docker/Dockerfile.aldous",
    live_update=[
        sync("app/", "/app/")
    ]
)

# Template aldous deployment with dynamic image tag
# Note: Image tag substitution handled by deployment itself
k8s_yaml('k8s/aldous-deployment.yaml')

k8s_yaml([
    'k8s/aldous-service.yaml',
    'k8s/aldous-ingress.yaml',
    'k8s/oidc-protection.yaml',
    'k8s/oidc-user.yaml',
    'k8s/oidc-client-sealed-secret.yaml',
    'k8s/cloudflare-origin-cert-sealed-secret.yaml',
    'k8s/kong-database-sealed-secret.yaml',
])



# Infrastructure setup - all handled by Tilt
local_resource(
  'microk8s_setup',
  cmd='sudo snap install microk8s --classic && sudo microk8s status --wait-ready',
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'microk8s_config',
  cmd='sudo microk8s config > ~/.kube/config',
  resource_deps=['microk8s_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'microk8s_addons',
  cmd='sudo microk8s enable community rook-ceph cloudnative-pg metallb:' + env["METALLB_RANGE"],
  resource_deps=['microk8s_config'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'ceph_setup',
  cmd='sudo snap install microceph --classic || true && sudo snap restart microceph && sleep 5 && sudo microceph cluster bootstrap && sudo microceph disk add loop,4G,3 && sleep 10 && until sudo ceph -s | grep -q "HEALTH_OK"; do sleep 1; done && CONF=$(sudo find /var/snap/microceph -name ceph.conf | head -n1) && KEYRING=$(sudo find /var/snap/microceph -name ceph.client.admin.keyring | head -n1) && sudo microk8s connect-external-ceph --ceph-conf "$CONF" --keyring "$KEYRING" --rbd-pool microk8s-rbd0 && until kubectl get pods -n rook-ceph --no-headers 2>/dev/null | grep -q .; do sleep 5; done && kubectl -n rook-ceph wait --for=condition=Ready pods --all --timeout=600s',
  resource_deps=['microk8s_addons'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'registry_setup',
  cmd='sudo microk8s enable registry:size=20Gi && until kubectl get pods -n container-registry --no-headers 2>/dev/null | grep -q Running; do echo "Waiting for registry pod..."; sleep 5; done',
  resource_deps=['ceph_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

# Build Kong image after registry is ready
local_resource(
  'kong_build',
  cmd='until curl -f http://localhost:32000/v2/ 2>/dev/null; do echo "Waiting for registry..."; sleep 5; done && docker build -t localhost:32000/kong-oidc:3.7.0 -f docker/Dockerfile.kong . && docker push localhost:32000/kong-oidc:3.7.0',
  resource_deps=['registry_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'minio_setup', 
  cmd='sudo microk8s enable minio',
  resource_deps=['ceph_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

# Kong CRDs will be installed by helm chart


# Helm deployments using helm_remote for remote charts
helm_remote('kong',
    repo_name='kong',
    repo_url='https://charts.konghq.com',
    values=['helm/kong-values.yaml'],
    set=[
        'image.repository=' + images['kong']['name'],
        'image.tag=' + images['kong']['tag'],
        'env.pg_host=' + env['PG_HOST']
    ])

helm_remote('keycloak',
    repo_name='bitnami', 
    repo_url='https://charts.bitnami.com/bitnami',
    values=['helm/keycloak-values.yaml'],
    set=[
        'externalDatabase.host=' + env['PG_HOST'],
        'extraEnv[1].value=http://' + env['MINIO_HOST'] + ':9000'
    ])

helm_remote('redis',
    repo_name='bitnami',
    repo_url='https://charts.bitnami.com/bitnami', 
    values=['helm/redis-values.yaml'])

helm_remote('memcached',
    repo_name='bitnami',
    repo_url='https://charts.bitnami.com/bitnami',
    values=['helm/memcached-values.yaml'])



# Flatten dependency graph using Helm releases and k8s resources
k8s_resource('kong-kong', resource_deps=['kong_build'])
k8s_resource('keycloak', resource_deps=['minio_setup'])
k8s_resource('aldous', port_forwards=['8000:8000'], resource_deps=['kong-kong', 'registry_setup'])

# Port forwarding handled by k8s_resource above
# Ingress check - manual trigger only
local_resource(
    'ingress_check',
    cmd='bash -c "until curl -sf https://aldous.info; do sleep 5; done && echo ingress OK"',
    resource_deps=['aldous'],
    env=env,
    trigger_mode=TRIGGER_MODE_MANUAL,
)
