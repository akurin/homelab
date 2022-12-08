#!/bin/bash
set -euo pipefail

read -r -p "Enter username: " username
read -r -p "Enter password: " password

helm upgrade --install dockerconfigjson ./dockerconfigjson \
	--set imageCredentials.registry=ghcr.io \
	--set imageCredentials.username="$username" \
	--set imageCredentials.password="$password"
