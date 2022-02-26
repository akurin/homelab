#!/bin/bash
set -euo pipefail

helm upgrade \
    --install ingress-nginx-internal ingress-nginx/ingress-nginx \
    --namespace kube-system \
    -f ingress-nginx/internal.yaml
