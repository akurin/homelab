#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook --inventory "./inventory/home.yml" home_tunnel.yml "$@")
