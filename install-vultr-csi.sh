#!/bin/bash
set -euo pipefail

apikey="$(pass vultr/apikey)"

helm upgrade --install --rollback-on-failure vultr-csi ./vultr-csi/ --set apiKey="$apikey"
