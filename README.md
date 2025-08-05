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
$ kubectl get po -A
NAMESPACE            NAME                                            READY   STATUS
cert-manager         cert-manager-7ff594b5bc-6qpp6                   1/1     Running
cert-manager         cert-manager-cainjector-fd9bf654b-zrmw8         1/1     Running
cert-manager         cert-manager-webhook-7749797f6-c9k9d            1/1     Running
cnpg-system          cnpg-controller-manager-7956b7c488-mj9bj        1/1     Running
container-registry   registry-579865c76c-67w9f                       1/1     Running
default              aldous-858fd46b69-25qln                         1/1     Running
default              aldous-858fd46b69-fv994                         1/1     Running
default              keycloak-0                                      1/1     Running
default              kong-kong-d4c64b5b-x4vq4                        2/2     Running
default              kong-kong-post-upgrade-migrations-mr8p5         0/1     Completed
default              kong-kong-pre-upgrade-migrations-2w9v5          0/1     Completed
default              memcached-58d6f5dfc9-4lz5q                      1/1     Running
default              pg-cluster-1                                    1/1     Running
default              redis-master-0                                  1/1     Running
kube-system          calico-kube-controllers-5947598c79-4vfcm        1/1     Running
kube-system          calico-node-b5h86                               1/1     Running
kube-system          coredns-79b94494c7-kf7mr                        1/1     Running
kube-system          hostpath-provisioner-c778b7559-8fc24            1/1     Running
metallb-system       controller-7ffc454778-t8g9n                     1/1     Running
metallb-system       speaker-5f8m8                                   1/1     Running
minio-operator       microk8s-microk8s-0                             2/2     Running
minio-operator       minio-operator-5898ffdfcb-kgmbq                 1/1     Running
minio-operator       minio-operator-5898ffdfcb-rnmgb                 1/1     Running
rook-ceph            csi-cephfsplugin-provisioner-7bd8fb7c64-6pdlh   5/5     Running
rook-ceph            csi-cephfsplugin-x6bpc                          2/2     Running
rook-ceph            csi-rbdplugin-mfjtl                             2/2     Running
rook-ceph            csi-rbdplugin-provisioner-5f7d95b6fb-dflr8      5/5     Running
rook-ceph            rook-ceph-operator-684bbd569f-zz2zx             1/1     Running
```
