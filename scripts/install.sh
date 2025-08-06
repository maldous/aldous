#!/usr/bin/env bash
set -euo pipefail
set -x

snap install microk8s --classic
microk8s status --wait-ready
mkdir -p ~/.kube
microk8s config > ~/.kube/config
microk8s enable community
microk8s enable rook-ceph
microk8s enable cloudnative-pg
microk8s enable metallb:${METALLB_RANGE}
