#!/bin/bash
set -euo pipefail

./terraform-apply.sh
./wait-for-hosts.sh
./ssh-hardening.sh
./ufw.sh
./install-tailscale.sh
./install-k3s.sh

chmod 600 ~/.kube/k3s-kubeconfig
export KUBECONFIG=~/.kube/k3s-kubeconfig

./install-cert-manager.sh
./install-rss-hub.sh
