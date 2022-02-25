#!/bin/bash
set -euo pipefail

./terraform-apply.sh

ip_address=$(cd terraform/ && terraform output -raw node-0_ipv4_address)
./route53.sh "$ip_address"

./install-k3s.sh

chmod 600 ~/.kube/k3s-kubeconfig
export KUBECONFIG=~/.kube/k3s-kubeconfig

./install-nginx.sh
./install-cert-manager.sh
./install-hello-world.sh
