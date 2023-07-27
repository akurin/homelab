#!/bin/bash
set -euo pipefail

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install ksm prometheus-community/kube-state-metrics --set image.tag=v2.4.2

password="$(pass grafana/apikey)"

helm upgrade \
	--set password="$password" \
	--install grafana-kuber ./grafana-kuber
