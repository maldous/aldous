# runme.sh

## Overview

The runme.sh script bootstraps a MicroK8s stack on Ubuntu, preparing a PHP/Laravel environment.

It cleans up any prior installation, connects to an external Ceph cluster, provisions object and block storage, deploys caching and database services, sets up an API gateway with OpenID Connect enforcement, and manages TLS certificates.

When it finishes, there will be pods for Keycloak, Kong, Memcached, Redis, PostgreSQL, MinIO operator, Registry and Cert-Manager.

## Steps

1. **Cleanup**
   Stop any existing MicroK8s daemons, unmount leftover volumes, delete network namespaces, and purge previous MicroK8s and MicroCeph snaps.

2. **MicroK8s Installation**
   Install MicroK8s via snap, wait for the control plane and core addons to become ready.

3. **Ceph Storage Backend**
   Create RBD and CephFS pools on the external Ceph cluster, configure size and replication settings, initialize the filesystem, and register it with MicroK8s for dynamic provisioning.

4. **MinIO Operator**
   Enable the MinIO operator addon against the Ceph RBD backend, wait for the operator and console pods to roll out, then create a default bucket for application use.

5. **Private Registry**
   Enable the built-in MicroK8s registry on CephFS storage, mark its StorageClass as default, and verify registry pods are running.

6. **PostgreSQL Cluster**
   Activate the CloudNativePG addon, remove the hostpath default StorageClass, deploy a single-node PostgreSQL cluster with persistent volumes, then create application databases and user roles via Kubernetes secrets.

7. **Caching Services**
   Install Memcached using the Bitnami Helm chart, then deploy Redis in standalone mode without authentication. Both services run in the default namespace for low-latency caching.

8. **Kong API Gateway**
   Add the Kong Helm repository, install or upgrade Kong pointing at the external PostgreSQL backend, expose it via LoadBalancer, and confirm that proxy and admin pods are healthy, along with the init-migrations job.

9. **Keycloak Identity Provider**
   Deploy Keycloak against the PostgreSQL cluster, expose it through Kong with TLS, set up the admin user and realm, enable self-registration, and enforce HTTPS-only access.

10. **OIDC Integration**
   Create a Kong consumer for OIDC users, apply a global plugin to enforce OpenID Connect using the configured Keycloak realm and client credentials.

## Result

After the script completes, the MicroK8s cluster has:

- Ceph-backed block and filesystem storage
- MinIO object storage operator with a default bucket
- A private Docker registry for local images
- CloudNativePG PostgreSQL cluster and three dedicated databases
- Memcached and Redis for caching workloads
- Kong API gateway securing routes and handling traffic
- Keycloak managing user authentication and token issuance
- A global Kong plugin enforcing OIDC on all incoming requests

## Summary
```

```
