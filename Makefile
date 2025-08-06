.PHONY: reset dev install help

dev:
	tilt up --stream

install:
	@echo "Installing Kind and required tools..."
	@if ! command -v kind >/dev/null 2>&1; then \
		echo "Installing Kind..."; \
		curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64; \
		chmod +x ./kind; \
		sudo mv ./kind /usr/local/bin/kind; \
	fi
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "Installing kubectl..."; \
		curl -LO "https://dl.k8s.io/release/$$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; \
		chmod +x kubectl; \
		sudo mv kubectl /usr/local/bin/kubectl; \
	fi
	@if ! command -v helm >/dev/null 2>&1; then \
		echo "Installing Helm..."; \
		curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; \
	fi
	@echo "All tools installed successfully!"

reset:
	@if [ "$(CONFIRM_RESET)" != "YES" ]; then \
		echo "Run: CONFIRM_RESET=YES make reset"; \
		exit 1; \
	fi
	@set -x; \
	echo "Stopping and removing Kind cluster..."; \
	kind delete cluster --name aldous || true; \
	echo "Stopping and removing registry container..."; \
	docker stop kind-registry || true; \
	docker rm kind-registry || true; \
	echo "Cleaning up Docker networks..."; \
	docker network rm kind || true; \
	echo "Cleaning up any remaining containers..."; \
	docker container prune -f || true; \
	echo "Cleaning up any remaining images..."; \
	docker image prune -f || true; \
	echo "Reset complete!"

status:
	@echo "=== Kind Cluster Status ==="
	@kind get clusters || echo "No Kind clusters found"
	@echo ""
	@echo "=== Registry Status ==="
	@docker ps --filter name=kind-registry --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "Registry not running"
	@echo ""
	@echo "=== Kubernetes Context ==="
	@kubectl config current-context 2>/dev/null || echo "No kubectl context set"
	@echo ""
	@echo "=== Pods Status ==="
	@kubectl get pods --all-namespaces 2>/dev/null || echo "Cannot connect to cluster"

logs:
	@echo "=== Recent Kind cluster logs ==="
	@kind export logs --name aldous /tmp/kind-logs 2>/dev/null && echo "Logs exported to /tmp/kind-logs" || echo "No logs available"

help:
	@echo "Available targets:"
	@echo "  install - Install Kind, kubectl, and Helm"
	@echo "  dev     - Start development environment with Tilt"
	@echo "  reset   - Destroy Kind cluster and cleanup (CONFIRM_RESET=YES)"
	@echo "  status  - Show cluster and component status"
	@echo "  logs    - Export Kind cluster logs"
	@echo "  help    - Show this help"
