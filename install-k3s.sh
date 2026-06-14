#!/bin/bash
set -euo pipefail

tailscale_auth_key=$(pass headscale/preauthkey_k3s)
GCLOUD_RW_API_KEY="$(pass grafana/alloy_token)"
GCLOUD_FM_URL="$(pass grafana/GCLOUD_FM_URL)"
GCLOUD_FM_POLL_FREQUENCY="$(pass grafana/GCLOUD_FM_POLL_FREQUENCY)"
GCLOUD_FM_HOSTED_ID="$(pass grafana/GCLOUD_FM_HOSTED_ID)"
K3S_TOKEN="$(pass k3s/token)"

LIMIT=()
[[ -n "${1:-}" ]] && LIMIT=(--limit "$1")

(
	cd ansible && ansible-playbook \
		k3s.yml \
		--inventory "./inventory/k3s.yml" \
		"${LIMIT[@]+"${LIMIT[@]}"}" \
		-e tailscale_auth_key="$tailscale_auth_key" \
		-e GCLOUD_RW_API_KEY="$GCLOUD_RW_API_KEY" \
		-e GCLOUD_FM_URL="$GCLOUD_FM_URL" \
		-e GCLOUD_FM_POLL_FREQUENCY="$GCLOUD_FM_POLL_FREQUENCY" \
		-e GCLOUD_FM_HOSTED_ID="$GCLOUD_FM_HOSTED_ID" \
		-e K3S_TOKEN="$K3S_TOKEN"
)
