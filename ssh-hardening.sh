#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook ssh-hardening.yml)
