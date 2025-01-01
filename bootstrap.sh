#!/bin/bash
set -euo pipefail

./bootstrap-terraform.sh
./provision-terraform-resources.sh
./wait-all.sh

./install-k3s.sh

export KUBECONFIG="$HOME/.kube/$TIER-k3s-kubeconfig"

./install-grafana-kuber.sh
./install-dockerconfigjson.sh

./install-cert-manager.sh
./install-cluster-issuer.sh

./install-inbucket.sh
