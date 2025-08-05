#!/usr/bin/env bash
set -euo pipefail
set -x

kubectl apply -f k8s/aldous-deployment.yaml
kubectl apply -f k8s/aldous-service.yaml
kubectl apply -f k8s/aldous-ingress.yaml
docker build -t localhost:32000/aldous:latest -f ../docker/Dockerfile.aldous .
docker push localhost:32000/aldous:latest
kubectl rollout restart deployment/aldous
