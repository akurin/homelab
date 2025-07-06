#!/bin/bash
set -euo pipefail

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

#helm upgrade --install --atomic alloy-operator grafana/alloy-operator

access_policy_token="$(pass grafana/alloy_token)"

helm upgrade --install --atomic \
	--values grafana-kuber/values.yaml \
	--set destinations[0].auth.password="$access_policy_token" \
	--set destinations[1].auth.password="$access_policy_token" \
	--set destinations[2].auth.password="$access_policy_token" \
	--set alloy-metrics.remoteConfig.auth.password="$access_policy_token" \
	--set alloy-singleton.remoteConfig.auth.password="$access_policy_token" \
	--set alloy-logs.remoteConfig.auth.password="$access_policy_token" \
	--set alloy-receiver.remoteConfig.auth.password="$access_policy_token" \
	grafana-k8s-monitoring grafana/k8s-monitoring
