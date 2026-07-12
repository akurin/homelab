#!/bin/bash
set -euo pipefail

tailscale_auth_key=$(pass headscale/preauthkey_k3s)
K3S_TOKEN="$(pass k3s/token)"

LIMIT=()
[[ -n "${1:-}" ]] && LIMIT=(--limit "$1")

(
	cd ansible && ansible-playbook \
		k3s.yml \
		--inventory "./inventory/k3s.yml" \
		"${LIMIT[@]+"${LIMIT[@]}"}" \
		-e tailscale_auth_key="$tailscale_auth_key" \
		-e K3S_TOKEN="$K3S_TOKEN"
)
