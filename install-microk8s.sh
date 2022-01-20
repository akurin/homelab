#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook microk8s.yml)
