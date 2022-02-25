#!/bin/bash
set -euo pipefail

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade \
    --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace kube-system \
    -f ingress-nginx/values.yaml
