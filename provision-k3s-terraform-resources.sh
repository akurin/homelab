#!/bin/bash
set -euo pipefail

VULTR_API_KEY="$(pass vultr/apikey)"

ssh_key_id=$(cd shared-terraform-resources && terraform output -raw ssh_key_id)

(
	cd k3s-terraform-resources &&
		terraform workspace select -or-create "$TIER" &&
		VULTR_API_KEY="$VULTR_API_KEY" terraform apply -var="ssh_key_id=$ssh_key_id"
)
