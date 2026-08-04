#!/bin/bash
set -euo pipefail

# --rollback-on-failure implies --wait, and on a *first* install there is no previous release
# to roll back to, so a timeout makes Helm uninstall what it just deployed instead. Wallabag's
# first boot runs `composer install` inside the container, which is slow on this cluster's
# single small node, so the default 5m timeout is not enough headroom — hence the explicit
# --timeout. (The PVC additionally carries helm.sh/resource-policy: keep so the database
# survives an uninstall regardless.)
helm upgrade --install --rollback-on-failure --timeout 15m \
	wallabag ./wallabag/ \
	--set domainName=https://wallabag.morjoff.com
