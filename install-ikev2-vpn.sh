#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook vpn.yml)
