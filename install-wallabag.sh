#!/bin/bash
set -euo pipefail

release=wallabag
domain=https://wallabag.morjoff.com
pass_entry=wallabag/admin

# The upstream image installs its admin account non-interactively, which means it always gets
# the documented defaults: wallabag/wallabag with ROLE_SUPER_ADMIN. There is no env var or
# parameter to override that, so the password can only be changed *after* the database exists.
#
# Publishing the ingress in the same step would therefore expose a super-admin account with
# known credentials, and Let's Encrypt lists every issued certificate in Certificate
# Transparency logs — so a fresh hostname is discoverable, and gets probed, within minutes.
#
# So a first install is done in two passes: bring it up unpublished, change the password, and
# only then create the ingress. Presence of the Ingress object is what marks the bootstrap as
# finished, rather than mere existence of the release: if the password step fails, the ingress
# is still absent, so the next run retries the bootstrap instead of publishing a default-
# credentialed instance.
if kubectl get ingress "$release" >/dev/null 2>&1; then
	helm upgrade --install --rollback-on-failure \
		"$release" ./wallabag/ \
		--set domainName="$domain" \
		"$@"
	exit 0
fi

if ! password="$(pass "$pass_entry" 2>/dev/null)"; then
	read -rsp "No '$pass_entry' in pass. Password for wallabag's admin account: " password
	echo
fi
[ -n "$password" ] || { echo "empty password, aborting" >&2; exit 1; }

echo "First install: bringing wallabag up unpublished..."
helm upgrade --install --rollback-on-failure \
	"$release" ./wallabag/ \
	--set domainName="$domain" \
	--set ingress.enabled=false \
	"$@"

# --rollback-on-failure implies --wait, so the pod is Ready by now — and readiness means
# /api/info answers, which only happens after the entrypoint has finished installing the
# database. Feed the password on stdin rather than as an argument so it stays out of the
# container's process list.
echo "Setting the admin password from ${pass_entry}..."
printf '%s\n' "$password" | kubectl exec -i "deploy/$release" -- \
	php bin/console fos:user:change-password wallabag --env=prod

echo "Publishing the ingress..."
helm upgrade --install --rollback-on-failure \
	"$release" ./wallabag/ \
	--set domainName="$domain" \
	"$@"
