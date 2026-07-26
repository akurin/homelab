#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook --inventory "./inventory" maintain.yml "$@")
