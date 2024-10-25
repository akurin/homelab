#!/bin/bash
set -euo pipefail

helm upgrade --install inbucket ./inbucket/helm-charts/inbucket \
	--set "authenticatedEmails[0]=$(pass inbucket/email)" \
	--set "oauth2Proxy.clientId=$(pass inbucket/clientId)" \
	--set "oauth2Proxy.clientSecret=$(pass inbucket/clientSecret)" \
	--set "oauth2Proxy.cookieSecret=$(openssl rand -base64 32 | tr -- '+/' '-_')"
