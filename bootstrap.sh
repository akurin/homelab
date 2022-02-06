#!/bin/bash
set -euo pipefail

./terraform-apply.sh
ip_address=$(cd terraform/ && terraform output -raw node-0_ipv4_address)

# ./wait-for-hosts.sh
# ./ufw.sh
# ./install-tailscale.sh
./install-k3s.sh
# ./ssh-hardening.sh

chmod 600 ~/.kube/k3s-kubeconfig
export KUBECONFIG=~/.kube/k3s-kubeconfig

./route53.sh "$ip_address"
helm repo update
./install-cert-manager.sh
./install-rss-hub.sh
./install-rss-bridge.sh
