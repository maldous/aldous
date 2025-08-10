.PHONY: up build install reset status logs lint policy help secrets tls-secret helm-repos tools registry generate-manifests

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

KIND_NAME := aldous
NAMESPACE := default

KIND_VERSION := v0.20.0
KUBECTL_VERSION := v1.27.3
HELM_VERSION := v3.14.4

up: 
	tilt up

build: secrets help-repos
	@if kind get clusters | grep -qx '$(KIND_NAME)'; then echo "Kind cluster $(KIND_NAME) exists"; \
	else kind create cluster --config kind-config.yaml --wait 5m; fi
	@kubectl config use-context "kind-$(KIND_NAME)" >/dev/null

tools:
	@echo "kind $(KIND_VERSION), kubectl $(KUBECTL_VERSION), helm $(HELM_VERSION)"

install:
	@if ! command -v kind >/dev/null 2>&1; then \
	  curl -Lo ./kind https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-linux-amd64; \
	  chmod +x ./kind; sudo mv ./kind /usr/local/bin/kind; \
	fi
	@if ! command -v kubectl >/dev/null 2>&1; then \
	  curl -LO "https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/linux/amd64/kubectl"; \
	  chmod +x kubectl; sudo mv kubectl /usr/local/bin/kubectl; \
	fi
	@if ! command -v helm >/dev/null 2>&1; then \
	  curl -fsSL https://raw.githubusercontent.com/helm/helm/$(HELM_VERSION)/scripts/get-helm-3 | bash; \
	fi

reset:
	@if [ "$(CONFIRM_RESET)" != "YES" ]; then \
	  echo "Run: CONFIRM_RESET=YES make reset"; exit 1; \
	fi
	@set -x; \
	kind delete cluster --name "$(KIND_NAME)" || true; \
	docker stop kind-registry >/dev/null 2>&1 || true; \
	docker rm kind-registry >/dev/null 2>&1 || true; \
	docker container prune -f || true; \
	docker image prune -f || true

status:
	@echo "=== Kind clusters ==="
	@kind get clusters || true
	@echo
	@echo "=== Kubernetes context ==="
	@kubectl config current-context 2>/dev/null || echo "No context"
	@echo
	@echo "=== Pods ==="
	@kubectl get pods -A 2>/dev/null || echo "No cluster"

logs:
	@echo "=== Export Kind logs ==="
	@kind export logs --name "$(KIND_NAME)" /tmp/kind-logs 2>/dev/null && echo "Logs at /tmp/kind-logs" || echo "No logs"

helm-repos:
	@helm repo add kong https://charts.konghq.com >/dev/null 2>&1 || true
	@helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
	@helm repo add minio https://charts.min.io/ >/dev/null 2>&1 || true
	@helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1 || true
	@helm repo update >/dev/null

lint: helm-repos
	@echo "Render Kong with values for syntax check"
	@helm template kong kong/kong -f helm/kong-values.yaml >/dev/null
	@echo "Render Redis for syntax check"
	@helm template redis bitnami/redis -f helm/redis-values.yaml >/dev/null
	@echo "Render MinIO for syntax check"
	@helm template minio minio/minio -f helm/minio-values.yaml >/dev/null

help:
	@echo "Targets:"
	@echo "  install           Install pinned kind, kubectl, helm"
	@echo "  tools             Print pinned versions"
	@echo "  build             Create Kind cluster if missing"
	@echo "  up                Start Tilt after secrets and repos"
	@echo "  secrets           Ensure base secrets exist"
	@echo "  tls-secret        Create or update Cloudflare origin cert"
	@echo "  generate-manifests Regenerate static k8s manifests from Helm charts"
	@echo "  lint              Render charts for syntax checks"
	@echo "  status            Show cluster and pod status"
	@echo "  logs              Export Kind logs"
	@echo "  reset             Delete cluster and prune Docker (CONFIRM_RESET=YES)"

secrets: tls-secret build
	@kubectl get secret keycloak-admin -n $(NAMESPACE) >/dev/null 2>&1 || \
	  kubectl create secret generic keycloak-admin \
	    -n $(NAMESPACE) \
	    --from-literal=admin-password="$$(openssl rand -base64 32)"
	@kubectl get secret oidc-client-secret -n $(NAMESPACE) >/dev/null 2>&1 || \
	  kubectl create secret generic oidc-client-secret \
	    -n $(NAMESPACE) \
	    --from-literal=client-secret="$$(openssl rand -base64 48)"
	@kubectl get secret minio-root-credentials -n $(NAMESPACE) >/dev/null 2>&1 || \
	  kubectl create secret generic minio-root-credentials \
	    -n $(NAMESPACE) \
	    --from-literal=root-user="$$(openssl rand -hex 12)" \
	    --from-literal=root-password="$$(openssl rand -base64 48)"
	@kubectl get secret pg-cluster-app -n $(NAMESPACE) >/dev/null 2>&1 || \
          kubectl create secret generic pg-cluster-app \
            -n $(NAMESPACE) \
            --from-literal=username=app \
            --from-literal=password="$$(openssl rand -base64 24)"

generate-manifests: helm-repos
	@echo "Regenerating static Kubernetes manifests..."
	@mkdir -p k8s/generated
	@helm template cnpg-operator cnpg/cloudnative-pg -f helm/cloudnative-pg-values.yaml > k8s/generated/cloudnative-pg-operator.yaml
	@cp k8s/pg-cluster.yaml k8s/generated/pg-cluster.yaml
	@helm template kong kong/kong -f helm/kong-values.yaml \
	  --set image.repository=localhost:5000/kong-oidc \
	  --set image.tag=3.11-ubuntu \
	  --set image.pullPolicy=IfNotPresent > k8s/generated/kong.yaml
	@helm template redis bitnami/redis -f helm/redis-values.yaml > k8s/generated/redis.yaml
	@helm template memcached bitnami/memcached -f helm/memcached-values.yaml > k8s/generated/memcached.yaml
	@helm template minio minio/minio -f helm/minio-values.yaml > k8s/generated/minio.yaml
	@helm template keycloak bitnami/keycloak -f helm/keycloak-values.yaml > k8s/generated/keycloak.yaml
	@echo "Static manifests regenerated in k8s/generated/"

tls-secret:
	@if kubectl get secret cloudflare-origin-cert -n $(NAMESPACE) >/dev/null 2>&1; then \
          echo "cloudflare-origin-cert exists"; \
        else \
          test -n "$${CERT:-}" -a -n "$${KEY:-}" || { echo "Set CERT and KEY"; exit 1; }; \
          kubectl create secret tls cloudflare-origin-cert --cert="$(CERT)" --key="$(KEY)" -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -; \
        fi
