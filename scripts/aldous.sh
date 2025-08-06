#!/usr/bin/env bash
set -euo pipefail
set -x

kubectl apply -f k8s/aldous-deployment.yaml
kubectl apply -f k8s/aldous-service.yaml
kubectl apply -f k8s/aldous-ingress.yaml
kubectl rollout restart deployment/aldous
