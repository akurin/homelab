#!/bin/bash
set -euo pipefail

# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# helm upgrade --install ksm prometheus-community/kube-state-metrics --set image.tag=v2.4.2

access_policy_token="$(pass grafana/access_policy_token)"

helm --debug upgrade \
	--values grafana-kuber/values.yaml \
	--set externalServices.prometheus.basicAuth.password="$access_policy_token" \
	--set externalServices.loki.basicAuth.password="$access_policy_token" \
	--set externalServices.tempo.basicAuth.password="$access_policy_token" \
	--install --atomic grafana-k8s-monitoring grafana/k8s-monitoring
