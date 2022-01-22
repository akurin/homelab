#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook wait-for-hosts.yml)
