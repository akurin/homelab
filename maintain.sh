#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook --inventory-file "./inventory/${TIER}_hosts.yml" maintain.yml)
