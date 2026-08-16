#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook --inventory "./inventory/xray.yml" ssh_jump.yml "$@")
