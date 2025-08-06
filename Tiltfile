config.define_string('metallb_range')
config.define_string('pg_host')
config.define_string('minio_host')
config.define_string('kong_image_name')
config.define_string('kong_image_tag')
config.define_string('aldous_image_name')
config.define_string('aldous_image_tag')

cfg = config.parse()

env = {
    "METALLB_RANGE": cfg.get("metallb_range") or "192.168.1.240-192.168.1.250",
    "PG_HOST":       cfg.get("pg_host")       or "pg-cluster-rw.default.svc.cluster.local",
    "MINIO_HOST":    cfg.get("minio_host")    or "microk8s-hl.minio-operator.svc.cluster.local",
    "IMAGE_NAME":    cfg.get("kong_image_name") or "localhost:32000/kong-oidc",
    "IMAGE_TAG":     cfg.get("kong_image_tag")  or "3.7.0",
}

docker_build(
    'localhost:32000/kong-oidc:3.7.0',
    context='.',
    dockerfile='docker/Dockerfile.kong',
    live_update=[
        sync('docker/Dockerfile.kong', '/tmp/dockerfile-kong')
    ]
)

docker_build(
    'localhost:32000/aldous:latest',
    context='.',
    dockerfile='docker/Dockerfile.aldous',
    live_update=[
        sync('docker/Dockerfile.aldous', '/tmp/dockerfile-aldous')
    ]
)

k8s_yaml([
    'k8s/aldous-deployment.yaml',
    'k8s/aldous-service.yaml',
    'k8s/aldous-ingress.yaml',
    'k8s/pg-cluster.yaml',
    'k8s/oidc-protection.yaml',
    'k8s/oidc-user.yaml',
    'k8s/kong-manifest.yaml',
    'k8s/keycloak-manifest.yaml',
    'k8s/memcached-manifest.yaml',
    'k8s/redis-manifest.yaml',
])

def script_res(name, path, deps_on=[], manual=False, allow_parallel=False, script_env=None):
    local_resource(
        name          = name,
        cmd           = "sudo -E bash " + path,
        deps          = [path],
        resource_deps = deps_on,
        env           = script_env or env,
        trigger_mode  = TRIGGER_MODE_MANUAL if manual else TRIGGER_MODE_AUTO,
        allow_parallel= allow_parallel,
    )

script_res('reset',              'scripts/reset.sh',              manual=True)
script_res('install',            'scripts/install.sh',            deps_on=['reset'])

local_resource(
    'kong_crds',
    cmd='kubectl apply -f https://raw.githubusercontent.com/Kong/charts/main/charts/kong/crds/custom-resource-definitions.yaml',
    deps=[],
    resource_deps=['install'],
    trigger_mode=TRIGGER_MODE_AUTO,
)
script_res('ceph',               'scripts/ceph.sh',               deps_on=['install'])
script_res('registry',           'scripts/registry.sh',           deps_on=['ceph'])
script_res('minio',              'scripts/minio.sh',              deps_on=['ceph'])
script_res('pg',                 'scripts/pg.sh',                 deps_on=['ceph'])
script_res('memcache_redis',     'scripts/memcache-redis.sh',     deps_on=['ceph'])
script_res('kong_deploy',        'scripts/kong.sh',               deps_on=['pg', 'registry', 'kong_crds'])
script_res('keycloak_install',   'scripts/keycloak-install.sh',   deps_on=['pg', 'minio', 'memcache_redis'])
script_res('keycloak_configure', 'scripts/keycloak-configure.sh', deps_on=['keycloak_install'])
script_res('aldous_deploy',      'scripts/aldous.sh',             deps_on=['kong_deploy', 'registry'])
script_res('port_forward',       'scripts/forward.sh',            deps_on=['aldous_deploy'], manual=True)

k8s_resource('kong-kong', resource_deps=['kong_deploy'])
k8s_resource('aldous', port_forwards='8000:8000', resource_deps=['aldous_deploy'])

local_resource(
    'ingress_check',
    cmd          = "bash -c 'until curl -sf https://aldous.info; do sleep 5; done && echo ingress OK'",
    resource_deps=['aldous_deploy'],
    env          = env,
    trigger_mode = TRIGGER_MODE_MANUAL,
)

