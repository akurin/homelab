#!/bin/bash
set -euo pipefail

./terraform-apply.sh
./ssh-hardening.sh
./ufw.sh
./install-tailscale.sh
./install-microk8s.sh
./merge-kubeconfig.sh
./install-cert-manager.sh
./install-rss-hub.sh
