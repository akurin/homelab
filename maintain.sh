#!/bin/bash
set -euo pipefail

(cd ansible && ansible-playbook --inventory-file "./inventory" maintain.yml)
