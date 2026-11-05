#!/bin/bash
set -euo pipefail

# Deploy the split Xray client to the home node. Render its config first:
# ./publish-xray-client-configs.sh generates ~/vpn/x13/... from the shared `x13`
# identity in pass xray/uuids.
(cd ansible && ansible-playbook --inventory "./inventory/k3s.yml" xray_client.yml "$@")
