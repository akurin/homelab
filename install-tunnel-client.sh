#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook --inventory "./inventory/tunnel_clients.yml" tunnel_client.yml "$@")
