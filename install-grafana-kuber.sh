#!/bin/bash
set -euo pipefail

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

access_policy_token="$(pass grafana/alloy_token)"

helm upgrade --install --atomic --timeout 300s \
	--version "^4" \
	--values grafana-kuber/values.yaml \
	--set destinations.grafana-cloud-metrics.auth.password="$access_policy_token" \
	--set destinations.grafana-cloud-logs.auth.password="$access_policy_token" \
	--set collectorCommon.alloy.remoteConfig.auth.password="$access_policy_token" \
	grafana-k8s-monitoring grafana/k8s-monitoring
