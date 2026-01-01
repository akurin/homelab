#!/bin/bash
set -euo pipefail

tailscale_auth_key=$(pass headscale/preauthkey_k3s)
GCLOUD_RW_API_KEY="$(pass grafana/alloy_token)"
GCLOUD_HOSTED_METRICS_URL="$(pass grafana/GCLOUD_HOSTED_METRICS_URL)"
GCLOUD_HOSTED_METRICS_ID="$(pass grafana/GCLOUD_HOSTED_METRICS_ID)"
GCLOUD_HOSTED_LOGS_URL="$(pass grafana/GCLOUD_HOSTED_LOGS_URL)"
GCLOUD_HOSTED_LOGS_ID="$(pass grafana/GCLOUD_HOSTED_LOGS_ID)"
GCLOUD_FM_URL="$(pass grafana/GCLOUD_FM_URL)"
GCLOUD_FM_POLL_FREQUENCY="$(pass grafana/GCLOUD_FM_POLL_FREQUENCY)"
GCLOUD_FM_HOSTED_ID="$(pass grafana/GCLOUD_FM_HOSTED_ID)"
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
		-e GCLOUD_HOSTED_LOGS_ID="$GCLOUD_HOSTED_LOGS_ID" \
		-e GCLOUD_FM_URL="$GCLOUD_FM_URL" \
		-e GCLOUD_FM_POLL_FREQUENCY="$GCLOUD_FM_POLL_FREQUENCY" \
		-e GCLOUD_FM_HOSTED_ID="$GCLOUD_FM_HOSTED_ID" \
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
		-e GCLOUD_FM_URL="$GCLOUD_FM_URL" \
		-e GCLOUD_FM_POLL_FREQUENCY="$GCLOUD_FM_POLL_FREQUENCY" \
		-e GCLOUD_FM_HOSTED_ID="$GCLOUD_FM_HOSTED_ID" \
		-e K3S_TOKEN="$K3S_TOKEN" \
		-e TIER="$TIER"
)
