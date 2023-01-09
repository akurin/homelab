#!/bin/bash
set -euo pipefail

apikey="$(pass vultr/apikey)"

helm upgrade --install vultr-csi ./vultr-csi/ --set apiKey="$apikey"
