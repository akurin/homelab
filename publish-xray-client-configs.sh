#!/bin/bash
set -euo pipefail

LIMIT=()
[[ -n "${1:-}" ]] && LIMIT=(--limit "$1")

xray_users_b64="$(pass xray/uuids | base64)"
secret_path="$(pass xray/secret_path)"
grpc_service_name="$(pass xray/grpc_service_name)"
subscriptions_json="$(pass xray/subscriptions)"

# Step 1: Generate per-host client configs
(
	cd ansible

	ansible-playbook xray_client_configs.yml \
		--inventory-file "./inventory/xray.yml" \
		"${LIMIT[@]+"${LIMIT[@]}"}" \
		-e xray_users_b64="$xray_users_b64" \
		-e secret_path="$secret_path" \
		-e grpc_service_name="$grpc_service_name"
)

# Step 2: Merge config files per subscription
echo "Merging subscription bundles..."
publish_users_json="$(printf '%s' "$subscriptions_json" | python3 scripts/merge-subscriptions.py)"
publish_users_yaml_b64="$(printf '%s' "$publish_users_json" | base64)"

# Step 3: Upload subscription bundles to publish server
(
	cd ansible

	ansible-playbook xray_publish_configs.yml \
		--inventory-file "./inventory/xray.yml" \
		"${LIMIT[@]+"${LIMIT[@]}"}" \
		-e publish_users_yaml_b64="$publish_users_yaml_b64"
)

# Step 4: Update Caddyfile with current token routes and reload Caddy
(
	cd ansible

	ansible-playbook caddy_reload.yml \
		--inventory-file "./inventory/xray.yml" \
		-e publish_users_yaml_b64="$publish_users_yaml_b64" \
		-e secret_path="$secret_path" \
		-e grpc_service_name="$grpc_service_name"
)
