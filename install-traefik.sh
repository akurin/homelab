#!/bin/bash
set -euo pipefail

helm repo add traefik https://helm.traefik.io/traefik
helm upgrade \
    --install traefik traefik/traefik \
    --namespace kube-system \
    -f traefik/values.yaml
