#!/bin/bash
set -euo pipefail

(
	cd ansible && ansible-playbook \
		xray.yml \
		--inventory-file "./inventory/xray.yml" \
		-e GCLOUD_RW_API_KEY="$(pass grafana/alloy_token)" \
		-e GCLOUD_FM_URL="$(pass grafana/GCLOUD_FM_URL)" \
		-e GCLOUD_FM_POLL_FREQUENCY="$(pass grafana/GCLOUD_FM_POLL_FREQUENCY)" \
		-e GCLOUD_FM_HOSTED_ID="$(pass grafana/GCLOUD_FM_HOSTED_ID)" \
		-e xray_users_yaml_b64="$(pass vless/uuids | base64)" \
		-e secret_path="$(pass vless/secret_path)" \
		-e warp_secret_key="$(pass vless/warp_secret_key)" \
		-e warp_public_key="$(pass vless/warp_public_key)" \
		-e freedns_username="$(pass freedns.afraid.org/username)" \
		-e freedns_password="$(pass freedns.afraid.org/password)"
)
