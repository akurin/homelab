#!/bin/bash
set -euo pipefail

LIMIT=()
[[ -n "${1:-}" ]] && LIMIT=(--limit "$1")

GCLOUD_RW_API_KEY="$(pass grafana/alloy_token)"
GCLOUD_FM_URL="$(pass grafana/GCLOUD_FM_URL)"
GCLOUD_FM_POLL_FREQUENCY="$(pass grafana/GCLOUD_FM_POLL_FREQUENCY)"
GCLOUD_FM_HOSTED_ID="$(pass grafana/GCLOUD_FM_HOSTED_ID)"
xray_users_b64="$(pass xray/uuids | base64)"
secret_path="$(pass xray/secret_path)"
freedns_username="$(pass freedns.afraid.org/username)"
freedns_password="$(pass freedns.afraid.org/password)"
subscriptions_json="$(pass xray/subscriptions)"

# Build publish_users list (name + token) for Ansible — needed by Caddy config
publish_users_json="$(printf '%s' "$subscriptions_json" | jq '[.[] | {name, token}]')"
publish_users_yaml_b64="$(printf '%s' "$publish_users_json" | base64)"

# Step 1: Deploy servers + generate Caddy config with subscription routes
(
	cd ansible

	ansible-playbook xray.yml \
		--inventory "./inventory/xray.yml" \
		"${LIMIT[@]+"${LIMIT[@]}"}" \
		-e GCLOUD_RW_API_KEY="$GCLOUD_RW_API_KEY" \
		-e GCLOUD_FM_URL="$GCLOUD_FM_URL" \
		-e GCLOUD_FM_POLL_FREQUENCY="$GCLOUD_FM_POLL_FREQUENCY" \
		-e GCLOUD_FM_HOSTED_ID="$GCLOUD_FM_HOSTED_ID" \
		-e xray_users_b64="$xray_users_b64" \
		-e secret_path="$secret_path" \
		-e freedns_username="$freedns_username" \
		-e freedns_password="$freedns_password" \
		-e publish_users_yaml_b64="$publish_users_yaml_b64"
)

# Step 2: Generate per-host client configs
(
	cd ansible

	ansible-playbook xray_client_configs.yml \
		--inventory "./inventory/xray.yml" \
		"${LIMIT[@]+"${LIMIT[@]}"}" \
		-e xray_users_b64="$xray_users_b64" \
		-e secret_path="$secret_path"
)

# Step 3: Merge config files per subscription
echo "Merging subscription bundles..."
printf '%s' "$subscriptions_json" | python3 scripts/merge-subscriptions.py >/dev/null

# Step 4: Upload subscription bundles to publish server
(
	cd ansible

	ansible-playbook xray_publish_configs.yml \
		--inventory "./inventory/xray.yml" \
		"${LIMIT[@]+"${LIMIT[@]}"}" \
		-e publish_users_yaml_b64="$publish_users_yaml_b64"
)
