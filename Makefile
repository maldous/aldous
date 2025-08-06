.PHONY: reset dev

dev:
	tilt up --stream

reset:
	@if [ "$(CONFIRM_RESET)" != "YES" ]; then \
		echo "Run: CONFIRM_RESET=YES make reset"; \
		exit 1; \
	fi
	@set -x; \
	if systemctl is-active --quiet snap.microk8s.daemon-apiserver; then \
		microk8s stop || true; \
		mount | awk '/microk8s\/common/ {print $$3}' | xargs -r -n1 sudo umount -l || true; \
		ip netns list | awk '{print $$1}' | xargs -r -n1 sudo ip netns delete || true; \
	fi; \
	snap list | grep -q microceph && snap stop microceph || true; \
	snap list | grep -q microk8s && snap stop microk8s || true; \
	mount | grep ceph | awk '{print $$3}' | xargs -r -n1 sudo umount -l || true; \
	if command -v rbd >/dev/null 2>&1; then \
		rbd device list 2>/dev/null | awk 'NR>1 {print $$4}' | xargs -r -n1 sudo rbd device unmap || true; \
	fi; \
	if [ -d /sys/bus/rbd/devices ]; then \
		for dev in /sys/bus/rbd/devices/*; do \
			[ -e "$$dev" ] || continue; \
			echo "$$(basename "$$dev")" | sudo tee /sys/bus/rbd/remove || true; \
		done; \
	fi; \
	sudo rm -f /dev/rbd* || true; \
	sudo killall -9 systemd-udevd || true; \
	ps -eo pid,stat,cmd | awk '$$2=="D" && $$3 ~ /udev-worker/ {print $$1}' | xargs -r sudo kill -9 || true; \
	sudo systemctl start systemd-udevd || true; \
	sudo snap remove microk8s --purge || true; \
	sudo snap remove microceph --purge || true; \
	sudo modprobe -r rbd || true; \
	sudo modprobe -r libceph || true; \
	sudo rm -rf /etc/ceph /var/lib/ceph /var/snap/microceph /var/snap/microk8s || true

help:
	@echo "Available targets:"
	@echo "  dev   - Start development environment with Tilt"
	@echo "  reset - Destroy entire cluster (CONFIRM_RESET=YES)"
	@echo "  help  - Show this help"
