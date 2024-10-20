#!/bin/bash
set -euo pipefail

GCLOUD_RW_API_KEY="$(pass grafana/access_policy_token)"
GCLOUD_HOSTED_METRICS_URL=$(pass grafana/GCLOUD_HOSTED_METRICS_URL)
GCLOUD_HOSTED_METRICS_ID=$(pass grafana/GCLOUD_HOSTED_METRICS_ID)
GCLOUD_HOSTED_LOGS_URL=$(pass grafana/GCLOUD_HOSTED_LOGS_URL)
GCLOUD_HOSTED_LOGS_ID=$(pass grafana/GCLOUD_HOSTED_LOGS_ID)

(
	cd ansible && ansible-playbook \
		xray.yml \
		--inventory-file "./inventory/vpn_vultr_hosts.yml" \
		--inventory-file "./inventory/vpn_other_hosts.yml" \
		-e GCLOUD_RW_API_KEY="$GCLOUD_RW_API_KEY" \
		-e GCLOUD_HOSTED_METRICS_URL="$GCLOUD_HOSTED_METRICS_URL" \
		-e GCLOUD_HOSTED_METRICS_ID="$GCLOUD_HOSTED_METRICS_ID" \
		-e GCLOUD_HOSTED_LOGS_URL="$GCLOUD_HOSTED_LOGS_URL" \
		-e GCLOUD_HOSTED_LOGS_ID="$GCLOUD_HOSTED_LOGS_ID" \
		-e uuid="$(pass vless/uuid)" \
		-e private_key="$(pass vless/private_key)" \
		-e public_key="$(pass vless/public_key)" \
		-e short_id="$(pass vless/short_id)"
)
