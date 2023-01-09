#!/bin/bash
set -euo pipefail

(
	cd ansible && ansible-playbook \
		wait_all.yml \
		--inventory-file "./inventory/${TIER}_hosts.yml"
)
