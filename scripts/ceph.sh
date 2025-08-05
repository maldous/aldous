#!/usr/bin/env bash
set -euo pipefail
set -x

snap install microceph
modprobe ceph
microceph cluster bootstrap
microceph disk add loop,512G,1
ceph config set mon mon_allow_pool_size_one true
ceph config set global osd_pool_default_size 1
ceph config set global osd_pool_default_min_size 1
ceph osd pool create microk8s-rbd0 32
ceph osd pool application enable microk8s-rbd0 rbd
ceph osd pool set microk8s-rbd0 size 1 --yes-i-really-mean-it
ceph osd pool set microk8s-rbd0 min_size 1 --yes-i-really-mean-it
ceph osd pool create microk8s-cephfs-meta 32
ceph osd pool application enable microk8s-cephfs-meta cephfs
ceph osd pool set microk8s-cephfs-meta size 1 --yes-i-really-mean-it
ceph osd pool set microk8s-cephfs-meta min_size 1 --yes-i-really-mean-it
ceph osd pool create microk8s-cephfs-data 64
ceph osd pool application enable microk8s-cephfs-data cephfs
ceph osd pool set microk8s-cephfs-data size 1 --yes-i-really-mean-it
ceph osd pool set microk8s-cephfs-data min_size 1 --yes-i-really-mean-it
ceph fs new microk8sfs microk8s-cephfs-meta microk8s-cephfs-data
until ceph -s | grep -q "volumes: 1/1 healthy"; do sleep 1; done
CONF=$(find /var/snap/microceph -name ceph.conf | head -n1)
KEYRING=$(find /var/snap/microceph -name ceph.client.admin.keyring | head -n1)
microk8s connect-external-ceph --ceph-conf "$CONF" --keyring "$KEYRING" --rbd-pool microk8s-rbd0
kubectl -n rook-ceph wait --for=condition=Ready pods --all --timeout=600s

