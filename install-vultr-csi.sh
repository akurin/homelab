#!/bin/bash
set -euo pipefail

apikey="$(pass vultr/apikey)"

helm upgrade --install --atomic vultr-csi ./vultr-csi/ --set apiKey="$apikey"
