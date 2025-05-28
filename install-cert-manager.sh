#!/bin/bash
set -euo pipefail

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install --atomic \
	cert-manager jetstack/cert-manager \
	--namespace cert-manager \
	--create-namespace \
	--version v1.17.2 \
	--set crds.enabled=true
