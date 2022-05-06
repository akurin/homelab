#!/bin/bash
set -euo pipefail

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install ksm prometheus-community/kube-state-metrics --set image.tag=v2.4.2

echo Enter loki/prometheus password:
read password

helm upgrade \
    --set prometheus.password=$password \
    --set logs.password=$password \
    --install grafana-kuber ./grafana-kuber
