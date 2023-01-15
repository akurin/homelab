#!/bin/bash
set -euo pipefail

kubeconfig_path="$HOME/.kube/local-k3s-kubeconfig"
vagrant ssh -c 'sudo cat /etc/rancher/k3s/k3s.yaml' > "$kubeconfig_path"

echo run the following command to work with k3s:
echo export KUBECONFIG="\"$kubeconfig_path\""
