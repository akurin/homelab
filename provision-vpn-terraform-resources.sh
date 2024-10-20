#!/bin/bash
set -euo pipefail

VULTR_API_KEY="$(pass vultr/apikey)"
export VULTR_API_KEY

(
	cd vpn-terraform-resources && terraform apply
)
