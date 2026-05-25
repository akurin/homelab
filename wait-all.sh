#!/bin/bash
set -euo pipefail

LIMIT=()
[[ -n "${1:-}" ]] && LIMIT=(--limit "$1")

(
	cd ansible && ansible-playbook \
		wait_all.yml \
		--inventory-file "./inventory/${TIER}_hosts.yml" \
		"${LIMIT[@]+"${LIMIT[@]}"}"
)
