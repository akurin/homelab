#!/bin/bash
set -euo pipefail

VULTR_API_KEY="$(pass vultr/apikey)"

(
	cd terraform-resources &&
		terraform workspace select "$TIER" &&
		VULTR_API_KEY="$VULTR_API_KEY" terraform apply
)
