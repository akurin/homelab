#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook k3s-node.yml)
