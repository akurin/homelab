#!/bin/bash
set -euo pipefail

tailscale_auth_key=$(pass tailscale/auth_key)
GCLOUD_API_KEY="$(pass grafana/apikey)"
GCLOUD_STACK_ID="$(pass grafana/stackid)"
GCLOUD_HOSTED_METRICS_URL=$(pass grafana/GCLOUD_HOSTED_METRICS_URL)
GCLOUD_HOSTED_METRICS_ID=$(pass grafana/GCLOUD_HOSTED_METRICS_ID)
GCLOUD_HOSTED_LOGS_URL=$(pass grafana/GCLOUD_HOSTED_LOGS_URL)
GCLOUD_HOSTED_LOGS_ID=$(pass grafana/GCLOUD_HOSTED_LOGS_ID)
k3s_token="$(pass k3s/token)"

(
	cd ansible && ansible-playbook \
		k3s_server.yml \
		--inventory-file "./inventory/${TIER}_hosts.yml" \
		-e tailscale_auth_key="$tailscale_auth_key" \
		-e GCLOUD_API_KEY="$GCLOUD_API_KEY" \
		-e GCLOUD_STACK_ID="$GCLOUD_STACK_ID" \
		-e GCLOUD_HOSTED_METRICS_URL="$GCLOUD_HOSTED_METRICS_URL" \
		-e GCLOUD_HOSTED_METRICS_ID="$GCLOUD_HOSTED_METRICS_ID" \
		-e GCLOUD_HOSTED_LOGS_URL="$GCLOUD_HOSTED_LOGS_URL" \
		-e GCLOUD_HOSTED_LOGS_ID="$GCLOUD_HOSTED_LOGS_ID" \
		-e k3s_token="$k3s_token" \
		-e tier="$TIER"
)

chmod 600 "$HOME/.kube/$TIER-k3s-kubeconfig"

(
	cd ansible && ansible-playbook \
		k3s_agent.yml \
		--inventory-file "./inventory/${TIER}_hosts.yml" \
		-e tailscale_auth_key="$tailscale_auth_key" \
		-e GCLOUD_API_KEY="$GCLOUD_API_KEY" \
		-e GCLOUD_STACK_ID="$GCLOUD_STACK_ID" \
		-e GCLOUD_HOSTED_METRICS_URL="$GCLOUD_HOSTED_METRICS_URL" \
		-e GCLOUD_HOSTED_METRICS_ID="$GCLOUD_HOSTED_METRICS_ID" \
		-e GCLOUD_HOSTED_LOGS_URL="$GCLOUD_HOSTED_LOGS_URL" \
		-e GCLOUD_HOSTED_LOGS_ID="$GCLOUD_HOSTED_LOGS_ID" \
		-e k3s_token="$k3s_token" \
		-e tier="$TIER"
)
