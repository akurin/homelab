#!/bin/bash
set -euo pipefail

./terraform-apply.sh
ip_address=$(cd terraform/ && terraform output -raw node-0_ipv4_address)

./install-k3s.sh

chmod 600 ~/.kube/k3s-kubeconfig
export KUBECONFIG=~/.kube/k3s-kubeconfig

./install-contour.sh

./route53.sh "$ip_address"
helm repo update
./install-cert-manager.sh
./install-rss-hub.sh
./install-rss-bridge.sh
