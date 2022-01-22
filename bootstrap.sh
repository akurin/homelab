#!/bin/bash
set -euo pipefail

./terraform-apply.sh
./wait-for-hosts.sh
./ssh-hardening.sh
./ufw.sh
./install-tailscale.sh
./install-microk8s.sh

chmod 600 ~/.kube/microk8s-kubeconfig
export KUBECONFIG=~/.kube/microk8s-kubeconfig

./install-cert-manager.sh
./install-rss-hub.sh
