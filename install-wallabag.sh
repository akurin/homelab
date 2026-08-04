#!/bin/bash
set -euo pipefail

# --rollback-on-failure implies --wait, and on a first install there is no previous release to
# roll back to, so a timeout uninstalls what was just deployed rather than reverting it.
# Wallabag's first boot runs `composer install` in the container and may not finish inside the
# default 5m on this cluster's single small node. That is survivable rather than destructive:
# the PVC carries helm.sh/resource-policy: keep, so the SQLite database outlives the release
# and re-running this script picks it back up. Worst case is a re-run.
helm upgrade --install --rollback-on-failure \
	wallabag ./wallabag/ \
	--set domainName=https://wallabag.morjoff.com
