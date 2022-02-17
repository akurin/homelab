#!/bin/bash
set -euo pipefail

helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade \
    --install contour-external bitnami/contour \
    --namespace kube-system \
    -f contour/external.yaml
    --set envoy.hostIPs.http=70.34.249.174
    --set envoy.hostIPs.https=70.34.249.174
helm upgrade \
    --install contour-internal bitnami/contour \
    --namespace kube-system \
    -f contour/internal.yaml
    --set envoy.hostIPs.http=100.91.228.60
    --set envoy.hostIPs.https=100.91.228.60
