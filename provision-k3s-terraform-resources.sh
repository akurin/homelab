#!/bin/bash
set -euo pipefail

VULTR_API_KEY="$(pass vultr/apikey)"

(
	cd k3s-terraform-resources &&
		terraform workspace select -or-create "$TIER" &&
		VULTR_API_KEY="$VULTR_API_KEY" terraform apply
)
