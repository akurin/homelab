#!/bin/bash
set -euo pipefail

tailscale_auth_key=$(pass tailscale/auth_key)
GCLOUD_RW_API_KEY="$(pass grafana/access_policy_token)"
GCLOUD_HOSTED_METRICS_URL=$(pass grafana/GCLOUD_HOSTED_METRICS_URL)
GCLOUD_HOSTED_METRICS_ID=$(pass grafana/GCLOUD_HOSTED_METRICS_ID)
GCLOUD_HOSTED_LOGS_URL=$(pass grafana/GCLOUD_HOSTED_LOGS_URL)
GCLOUD_HOSTED_LOGS_ID=$(pass grafana/GCLOUD_HOSTED_LOGS_ID)
K3S_TOKEN="$(pass k3s/token)"

(
	cd ansible && ansible-playbook \
		k3s_server.yml \
		--inventory-file "./inventory/${TIER}_hosts.yml" \
		-e tailscale_auth_key="$tailscale_auth_key" \
		-e GCLOUD_RW_API_KEY="$GCLOUD_RW_API_KEY" \
		-e GCLOUD_HOSTED_METRICS_URL="$GCLOUD_HOSTED_METRICS_URL" \
		-e GCLOUD_HOSTED_METRICS_ID="$GCLOUD_HOSTED_METRICS_ID" \
		-e GCLOUD_HOSTED_LOGS_URL="$GCLOUD_HOSTED_LOGS_URL" \
		-e GCLOUD_HOSTED_LOGS_ID="$GCLOUD_HOSTED_LOGS_ID"
	-e K3S_TOKEN="$K3S_TOKEN" \
		-e TIER="$TIER"
)

chmod 600 "$HOME/.kube/$TIER-k3s-kubeconfig"

(
	cd ansible && ansible-playbook \
		k3s_agent.yml \
		--inventory-file "./inventory/${TIER}_hosts.yml" \
		-e tailscale_auth_key="$tailscale_auth_key" \
		-e GCLOUD_RW_API_KEY="$GCLOUD_RW_API_KEY" \
		-e GCLOUD_HOSTED_METRICS_URL="$GCLOUD_HOSTED_METRICS_URL" \
		-e GCLOUD_HOSTED_METRICS_ID="$GCLOUD_HOSTED_METRICS_ID" \
		-e GCLOUD_HOSTED_LOGS_URL="$GCLOUD_HOSTED_LOGS_URL" \
		-e GCLOUD_HOSTED_LOGS_ID="$GCLOUD_HOSTED_LOGS_ID" \
		-e K3S_TOKEN="$K3S_TOKEN" \
		-e TIER="$TIER"
)
