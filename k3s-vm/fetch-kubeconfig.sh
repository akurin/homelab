#!/bin/bash
set -euo pipefail

kubeconfig=$(mktemp)
vagrant ssh -c 'sudo cat /etc/rancher/k3s/k3s.yaml' >"$kubeconfig"

echo run the following command to work with k3s:
echo export KUBECONFIG="$kubeconfig"
