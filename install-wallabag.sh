#!/bin/bash
set -euo pipefail

helm upgrade --install --rollback-on-failure \
	wallabag ./wallabag/ \
	--set domainName=https://wallabag.morjoff.com
