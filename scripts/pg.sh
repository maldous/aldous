#!/usr/bin/env bash
set -euo pipefail
set -x

kubectl -n cnpg-system wait --for=condition=Ready pods --all --timeout=600s
kubectl delete sc microk8s-hostpath
kubectl apply -f k8s/pg-cluster.yaml
kubectl -n default wait cluster/pg-cluster --for=condition=Ready --timeout=600s
PG_POD=$(kubectl -n default get pods -l cnpg.io/cluster=pg-cluster -o jsonpath='{.items[0].metadata.name}')
kubectl -n default exec -i "$PG_POD" -- psql -U postgres <<'EOF'
CREATE ROLE aldous LOGIN PASSWORD 'aldous';
CREATE DATABASE aldous OWNER aldous ENCODING 'UTF8';
CREATE ROLE keycloak LOGIN PASSWORD 'keycloak';
CREATE DATABASE keycloak OWNER keycloak ENCODING 'UTF8';
CREATE ROLE kong LOGIN PASSWORD 'kong';
CREATE DATABASE kong OWNER kong ENCODING 'UTF8';
EOF
kubectl -n default create secret generic aldous-pg --dry-run=client -o yaml --from-literal=username=aldous --from-literal=password=aldous --from-literal=database=aldous | kubectl apply -f -
kubectl -n default create secret generic keycloak-pg --dry-run=client -o yaml --from-literal=username=keycloak --from-literal=password=keycloak --from-literal=database=keycloak | kubectl apply -f -
