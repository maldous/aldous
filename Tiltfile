load('ext://git_resource', 'git_checkout')

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
        "tag": cfg.get("kong_image_tag") or commit_sha
    },
    "aldous": {
        "name": "localhost:32000/aldous", 
        "tag": cfg.get("aldous_image_tag") or commit_sha
    }
}

env = {
    "METALLB_RANGE": cfg.get("metallb_range") or "192.168.1.240-192.168.1.250",
    "PG_HOST":       cfg.get("pg_host")       or "pg-cluster-rw.default.svc.cluster.local",
    "MINIO_HOST":    cfg.get("minio_host")    or "microk8s-hl.minio-operator.svc.cluster.local",
}

# Generic builder helper
def build_image(name, context, dockerfile, sync_paths, build_args=None):
    ref = f"{images[name]['name']}:{images[name]['tag']}"
    docker_build(ref,
        context=context,
        dockerfile=dockerfile,
        build_args=build_args or {},
        live_update=[sync(src, dst) for src, dst in sync_paths],
        skip_push=bool(os.getenv("TILT_SKIP_PUSH"))
    )
    return ref

# Build images with improved caching and live updates
kong_ref = build_image("kong", ".", "docker/Dockerfile.kong", 
    [("docker/Dockerfile.kong", "/tmp/Dockerfile.kong")])

aldous_ref = docker_build(
    f"{images['aldous']['name']}:{images['aldous']['tag']}",
    context=".",
    dockerfile="docker/Dockerfile.aldous",
    live_update=[
        sync("app/", "/app/"),
        restart_container()
    ],
    skip_push=bool(os.getenv("TILT_SKIP_PUSH"))
)

# Template aldous deployment with dynamic image tag
k8s_yaml(kustomize_sub("k8s/aldous-deployment.yaml", {
    "ALDOUS_TAG": images['aldous']['tag']
}))

k8s_yaml([
    'k8s/aldous-service.yaml',
    'k8s/aldous-ingress.yaml',
    'k8s/pg-cluster.yaml',
    'k8s/oidc-protection.yaml',
    'k8s/oidc-user.yaml',
    'k8s/oidc-client-sealed-secret.yaml',
    'k8s/cloudflare-origin-cert-sealed-secret.yaml',
    'k8s/kong-database-sealed-secret.yaml',
])



# Infrastructure setup - all handled by Tilt
local_resource(
  'microk8s_setup',
  cmd='snap install microk8s --classic && microk8s status --wait-ready',
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'microk8s_config',
  cmd='microk8s config > ~/.kube/config',
  resource_deps=['microk8s_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'microk8s_addons',
  cmd='microk8s enable community rook-ceph cloudnative-pg metallb:' + env["METALLB_RANGE"],
  resource_deps=['microk8s_config'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'ceph_setup',
  cmd='snap install microceph --classic && microceph cluster bootstrap && microceph disk add loop,4G,3 && sleep 10 && until ceph -s | grep -q "volumes: 1/1 healthy"; do sleep 1; done && CONF=$(find /var/snap/microceph -name ceph.conf | head -n1) && KEYRING=$(find /var/snap/microceph -name ceph.client.admin.keyring | head -n1) && microk8s connect-external-ceph --ceph-conf "$CONF" --keyring "$KEYRING" --rbd-pool microk8s-rbd0 && until kubectl get pods -n rook-ceph --no-headers 2>/dev/null | grep -q .; do sleep 5; done && kubectl -n rook-ceph wait --for=condition=Ready pods --all --timeout=600s',
  resource_deps=['microk8s_addons'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'registry_setup',
  cmd='microk8s enable registry:size=20Gi',
  resource_deps=['ceph_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

local_resource(
  'minio_setup', 
  cmd='microk8s enable minio',
  resource_deps=['ceph_setup'],
  trigger_mode=TRIGGER_MODE_AUTO,
)

k8s_yaml("https://raw.githubusercontent.com/Kong/charts/main/charts/kong/crds/custom-resource-definitions.yaml")


# Helm deployments with templated values
helm("kong", "kong/kong", 
     values=["helm/kong-values.yaml"],
     set=[
         "image.repository=" + images["kong"]["name"],
         "image.tag=" + images["kong"]["tag"],
         "env.pg_host=" + env["PG_HOST"]
     ])
helm("keycloak", "bitnami/keycloak", 
     values=["helm/keycloak-values.yaml"],
     set=[
         "externalDatabase.host=" + env["PG_HOST"],
         "extraEnv[1].value=http://" + env["MINIO_HOST"] + ":9000"
     ])
helm("redis", "bitnami/redis", 
     values=["helm/redis-values.yaml"])
helm("memcached", "bitnami/memcached", 
     values=["helm/memcached-values.yaml"])



# Flatten dependency graph using Helm releases and k8s resources
k8s_resource('pg-cluster', resource_deps=['ceph_setup'])
k8s_resource('minio-operator', resource_deps=['minio_setup'])
k8s_resource('kong-kong', resource_deps=['pg-cluster', 'registry_setup', 'kong'])
k8s_resource('keycloak', resource_deps=['pg-cluster', 'minio-operator', 'redis', 'memcached'])
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
