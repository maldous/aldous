# Aldous Tilt Environment Setup

This project has been converted from a shell script-based deployment (`runme.sh`) to a professional Tilt environment for better development workflow.

## Prerequisites

- Ubuntu/Debian system with sudo access
- [Tilt](https://tilt.dev/) installed
- Docker installed
- At least 8GB RAM and 20GB disk space

## Quick Start

1. **Start the environment:**
   ```bash
   tilt up
   ```

2. **Reset environment (if needed):**
   - In Tilt UI, manually trigger the `reset` resource
   - Or run: `tilt trigger reset`

3. **Access services:**
   - Aldous App: http://localhost:8000
   - Kong Admin: http://localhost:8080
   - Keycloak: http://localhost:8081
   - Production: https://aldous.info (after ingress setup)

## Architecture

### Docker Images
- **Kong Gateway**: Custom image with OIDC plugin (`localhost:32000/kong-oidc:3.7.0`)
- **Aldous App**: PHP application (`localhost:32000/aldous:latest`)

### Infrastructure Components
1. **MicroK8s**: Kubernetes cluster
2. **Ceph**: Distributed storage
3. **PostgreSQL**: Database (CloudNativePG)
4. **MinIO**: S3-compatible object storage
5. **Redis**: Caching and sessions
6. **Memcached**: Additional caching
7. **Kong**: API Gateway with OIDC
8. **Keycloak**: Identity and Access Management
9. **cert-manager**: TLS certificate management

## Tilt Resources

### Setup Pipeline (Auto-triggered)
1. `install` - Sets up MicroK8s with addons
2. `ceph` - Configures Ceph storage
3. `registry` - Enables Docker registry
4. `minio` - Sets up object storage
5. `pg` - Deploys PostgreSQL cluster
6. `memcache_redis` - Installs caching services
7. `certificate` - Sets up TLS certificates
8. `kong_deploy` - Deploys Kong Gateway
9. `keycloak_install` - Installs Keycloak
10. `keycloak_configure` - Configures OIDC
11. `aldous_deploy` - Deploys main application

### Manual Resources
- `reset` - Clean environment reset
- `port_forward` - Enable local port forwarding
- `ingress_check` - Test ingress connectivity

## Configuration

Environment variables can be customized via Tilt config:

```bash
# Example: Custom MetalLB range
tilt up -- --metallb_range="10.0.0.100-10.0.0.110"

# Example: Custom image names
tilt up -- --kong_image_name="myregistry/kong" --kong_image_tag="latest"
```

## Development Workflow

1. **Code Changes**: Edit Dockerfiles or K8s manifests
2. **Auto-rebuild**: Tilt automatically rebuilds and redeploys
3. **Live Updates**: Fast sync for development files
4. **Port Forwarding**: Access services locally

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure user is in `microk8s` group or run Tilt with sudo
2. **Resource Conflicts**: Use `reset` resource to clean state
3. **Storage Issues**: Check Ceph cluster health
4. **Network Issues**: Verify MetalLB IP range

### Logs and Debugging

- **Tilt UI**: http://localhost:10350
- **Resource Logs**: Click on any resource in Tilt UI
- **Kubernetes Logs**: `kubectl logs <pod-name>`
- **Service Status**: `kubectl get pods,svc,ingress`

### Manual Commands

```bash
# Check cluster status
microk8s status

# View all resources
kubectl get all

# Check storage
kubectl get pv,pvc

# Test connectivity
curl -k https://aldous.info
```

## Security Notes

- Default passwords are used for development
- Cloudflare API token is included (staging only)
- TLS uses Let's Encrypt staging environment
- OIDC is configured for `aldous.info` domain

## Migration from runme.sh

The original `runme.sh` script has been replaced with this Tilt environment:

- **Docker builds** moved to Tilt's `docker_build()`
- **Script execution** managed by Tilt resources
- **Dependencies** properly defined
- **Live updates** enabled for faster development
- **Port forwarding** integrated
- **Resource monitoring** via Tilt UI

## Next Steps

1. Customize the Aldous application in `docker/Dockerfile.aldous`
2. Modify Kong configuration in `scripts/kong.sh`
3. Update Keycloak settings in `scripts/keycloak-configure.sh`
4. Add your application code to the Docker context
