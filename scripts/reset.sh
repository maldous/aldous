#!/usr/bin/env bash
set -euo pipefail
set -x

if systemctl is-active --quiet snap.microk8s.daemon-apiserver; then
    microk8s stop || true
    mount | awk '/microk8s\/common/ {print $3}' | xargs -r -n1 umount -l || true
    ip netns list | awk '{print $1}' | xargs -r -n1 ip netns delete || true
fi

snap list | grep -q microceph && snap stop microceph || true
snap list | grep -q microk8s && snap stop microk8s || true

mount | grep ceph | awk '{print $3}' | xargs -r -n1 umount -l || true

if command -v rbd >/dev/null 2>&1; then
    rbd device list 2>/dev/null | awk 'NR>1 {print $4}' \
    | xargs -r -n1 rbd device unmap || true
fi

if [ -d /sys/bus/rbd/devices ]; then
    for dev in /sys/bus/rbd/devices/*; do
        [ -e "$dev" ] || continue
        echo "$(basename "$dev")" | tee /sys/bus/rbd/remove || true
    done
fi

rm -f /dev/rbd* || true

killall -9 systemd-udevd udevd || true
ps -eo pid,stat,cmd | awk '$2=="D" && $3 ~ /udev-worker/ {print $1}' | xargs -r kill -9 || true
systemctl start systemd-udevd || true

snap remove microk8s --purge || true
snap remove microceph --purge || true

modprobe -r rbd || true
modprobe -r libceph || true

rm -rf /etc/ceph /var/lib/ceph /var/snap/microceph /var/snap/microk8s || true
