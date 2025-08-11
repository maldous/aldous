.PHONY: build generate-manifests helm-repos help reset secrets tls-secret tools up

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := up

KIND_NAME := aldous
NAMESPACE := default
KIND_VERSION := v0.20.0
KUBECTL_VERSION := v1.27.3
HELM_VERSION := v3.14.4

up:
	tilt up

install: tools build helm-repos secrets generate-manifests

tools:
	@command -v kind >/dev/null 2>&1 || { curl -sSLo ./kind https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind; }
	@command -v kubectl >/dev/null 2>&1 || { curl -sSLo ./kubectl https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/linux/amd64/kubectl && chmod +x ./kubectl && sudo mv ./kubectl /usr/local/bin/kubectl; }
	@command -v helm >/dev/null 2>&1 || { curl -sS https://raw.githubusercontent.com/helm/helm/$(HELM_VERSION)/scripts/get-helm-3 | bash >/dev/null; }

build:
	@kind get clusters 2>/dev/null | grep -qx '$(KIND_NAME)' || kind create cluster --config kind-config.yaml --wait 5m >/dev/null
	@kubectl config use-context "kind-$(KIND_NAME)" >/dev/null 2>&1

helm-repos:
	@helm repo add kong https://charts.konghq.com >/dev/null 2>&1 || true
	@helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
	@helm repo add minio https://charts.min.io/ >/dev/null 2>&1 || true
	@helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1 || true
	@helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
	@helm repo add meilisearch https://meilisearch.github.io/meilisearch-kubernetes >/dev/null 2>&1 || true
	@helm repo add codecentric https://codecentric.github.io/helm-charts >/dev/null 2>&1 || true
	@helm repo update >/dev/null

secrets:
	@kubectl get secret keycloak-admin -n $(NAMESPACE) >/dev/null 2>&1 || kubectl create secret generic keycloak-admin -n $(NAMESPACE) --from-literal=admin-password="$$(openssl rand -base64 32)" >/dev/null
	@kubectl get secret oidc-client-secret -n $(NAMESPACE) >/dev/null 2>&1 || kubectl create secret generic oidc-client-secret -n $(NAMESPACE) --from-literal=client-secret="$$(openssl rand -base64 48)" >/dev/null
	@kubectl get secret minio-root-credentials -n $(NAMESPACE) >/dev/null 2>&1 || kubectl create secret generic minio-root-credentials -n $(NAMESPACE) --from-literal=root-user="$$(openssl rand -hex 12)" --from-literal=root-password="$$(openssl rand -base64 48)" >/dev/null
	@kubectl get secret pg-cluster-app -n $(NAMESPACE) >/dev/null 2>&1 || kubectl create secret generic pg-cluster-app -n $(NAMESPACE) --from-literal=username=app --from-literal=password="$$(openssl rand -base64 24)" >/dev/null
	@if [ ! -f .env ]; then \
	  DBPASS=$$(kubectl get secret pg-cluster-app -n $(NAMESPACE) -o jsonpath='{.data.password}' 2>/dev/null | base64 -d); \
	  APPKEY=$$(pwgen -s 32 1); \
	  printf 'APP_ENV=local\nAPP_DEBUG=true\nAPP_KEY=%s\nAPP_URL=http://localhost\nLOG_CHANNEL=stderr\nLOG_LEVEL=debug\nDB_CONNECTION=pgsql\nDB_HOST=pg-cluster-1-rw\nDB_PORT=5432\nDB_DATABASE=aldous\nDB_USERNAME=app\nDB_PASSWORD=%s\nCACHE_STORE=redis\nQUEUE_CONNECTION=redis\nSESSION_DRIVER=redis\nSESSION_LIFETIME=120\nREDIS_HOST=redis-master\nREDIS_PORT=6379\nREDIS_PASSWORD=\nMAIL_MAILER=smtp\nMAIL_HOST=mailhog\nMAIL_PORT=1025\nMAIL_ENCRYPTION=null\nMAIL_FROM_ADDRESS=root@aldous.info\nMAIL_FROM_NAME="root"\nFILESYSTEM_DISK=local\nMINIO_ENDPOINT=minio\nMINIO_USE_PATH_STYLE_ENDPOINT=true\n' "$$APPKEY" "$$DBPASS" > .env; \
	  echo "Created .env"; \
	fi
	@kubectl create secret generic app-env -n $(NAMESPACE) --from-env-file=.env --dry-run=client -o yaml | kubectl apply -f - >/dev/null

generate-manifests: helm-repos
	@mkdir -p k8s/generated
	@helm template cnpg-operator cnpg/cloudnative-pg -f helm/cloudnative-pg-values.yaml --no-hooks > k8s/generated/cloudnative-pg-operator.yaml
	@cp k8s/pg-cluster.yaml k8s/generated/pg-cluster.yaml
	@helm template kong kong/kong -f helm/kong-values.yaml --set image.repository=localhost:5000/kong-oidc --set image.tag=3.11-ubuntu --set image.pullPolicy=IfNotPresent > k8s/generated/kong.yaml
	@helm template redis bitnami/redis -f helm/redis-values.yaml --no-hooks > k8s/generated/redis.yaml
	@helm template memcached bitnami/memcached -f helm/memcached-values.yaml --no-hooks > k8s/generated/memcached.yaml
	@helm template minio minio/minio -f helm/minio-values.yaml --no-hooks > k8s/generated/minio.yaml
	@helm template keycloak bitnami/keycloak -f helm/keycloak-values.yaml --no-hooks > k8s/generated/keycloak.yaml
	@helm template loki grafana/loki -n observability -f helm/loki-values.yaml --no-hooks > k8s/generated/loki.yaml
	@helm template tempo grafana/tempo -n observability -f helm/tempo-values.yaml --no-hooks > k8s/generated/tempo.yaml
	@helm template grafana grafana/grafana -n observability -f helm/grafana-values.yaml --no-hooks > k8s/generated/grafana.yaml
	@helm template alloy grafana/alloy -n observability -f helm/alloy-values.yaml --no-hooks > k8s/generated/alloy.yaml
	@helm template prometheus prometheus-community/prometheus -n observability -f helm/prometheus-values.yaml --no-hooks > k8s/generated/prometheus.yaml
	@helm template mailhog codecentric/mailhog -n tools -f helm/mailhog-values.yaml --no-hooks > k8s/generated/mailhog.yaml
	@helm template meilisearch meilisearch/meilisearch -n tools -f helm/meilisearch-values.yaml --no-hooks > k8s/generated/meilisearch.yaml

reset:
	@kind delete cluster --name "$(KIND_NAME)" >/dev/null 2>&1 || true
	@docker stop kind-registry >/dev/null 2>&1 || true
	@docker rm kind-registry >/dev/null 2>&1 || true
	@docker container prune -f >/dev/null 2>&1 || true
	@docker image prune -f >/dev/null 2>&1 || true

tls-secret:
	@test -n "$${CERT:-}" && test -n "$${KEY:-}"
	@kubectl get secret cloudflare-origin-cert -n $(NAMESPACE) >/dev/null 2>&1 || kubectl create secret tls cloudflare-origin-cert --cert="$(CERT)" --key="$(KEY)" -n $(NAMESPACE) >/dev/null

help:
	@echo "Targets:"
	@echo "  up         Start Tilt after full install"
	@echo "  install    Prepare tools, cluster, repos, secrets, manifests (auto-generates .env and app-env)"
	@echo "  reset      Tear down cluster and prune Docker"
	@echo "  tls-secret Create or update Cloudflare origin cert (set CERT and KEY)"
