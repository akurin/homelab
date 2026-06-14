#!/bin/bash
set -euo pipefail

LIMIT=()
[[ -n "${1:-}" ]] && LIMIT=(--limit "$1")

(cd ansible && ansible-playbook --inventory "./inventory" "${LIMIT[@]+"${LIMIT[@]}"}" maintain.yml)
