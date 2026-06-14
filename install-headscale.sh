#!/bin/bash
set -euo pipefail

GCLOUD_RW_API_KEY="$(pass grafana/alloy_token)"
GCLOUD_FM_URL="$(pass grafana/GCLOUD_FM_URL)"
GCLOUD_FM_POLL_FREQUENCY="$(pass grafana/GCLOUD_FM_POLL_FREQUENCY)"
GCLOUD_FM_HOSTED_ID="$(pass grafana/GCLOUD_FM_HOSTED_ID)"

HEADSCALE_OIDC_ISSUER="$(pass headscale/oidc_issuer)"
HEADSCALE_OIDC_CLIENT_ID="$(pass headscale/oidc_client_id)"
HEADSCALE_OIDC_CLIENT_SECRET="$(pass headscale/oidc_client_secret)"
HEADSCALE_OIDC_ALLOWED_USER="$(pass headscale/oidc_allowed_user)"

LIMIT=()
[[ -n "${1:-}" ]] && LIMIT=(--limit "$1")

(
	cd ansible && ansible-playbook \
		headscale.yml \
		--inventory "./inventory/shared_hosts.yml" \
		"${LIMIT[@]+"${LIMIT[@]}"}" \
		-e GCLOUD_RW_API_KEY="$GCLOUD_RW_API_KEY" \
		-e GCLOUD_FM_URL="$GCLOUD_FM_URL" \
		-e GCLOUD_FM_POLL_FREQUENCY="$GCLOUD_FM_POLL_FREQUENCY" \
		-e GCLOUD_FM_HOSTED_ID="$GCLOUD_FM_HOSTED_ID" \
		-e headscale_oidc_issuer="$HEADSCALE_OIDC_ISSUER" \
		-e headscale_oidc_client_id="$HEADSCALE_OIDC_CLIENT_ID" \
		-e headscale_oidc_client_secret="$HEADSCALE_OIDC_CLIENT_SECRET" \
		-e headscale_oidc_allowed_user="$HEADSCALE_OIDC_ALLOWED_USER"
)
