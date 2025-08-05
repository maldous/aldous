#!/usr/bin/env bash
set -euo pipefail
set -x

kubectl create secret tls cloudflare-origin-cert --cert=../../.origin.crt --key=../../.origin.key -n default
