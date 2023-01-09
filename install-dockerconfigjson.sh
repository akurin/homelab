#!/bin/bash
set -euo pipefail

username=$(pass github/username)
password=$(pass github/password)

helm upgrade --install dockerconfigjson ./dockerconfigjson \
	--set imageCredentials.registry=ghcr.io \
  --set imageCredentials.username="$username" \
  --set imageCredentials.password="$password"
