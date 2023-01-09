#!/bin/bash
set -euo pipefail

./bootstrap-terraform.sh
./provision-terraform-resources.sh
./wait-all.sh

./install-k3s.sh

export KUBECONFIG="$HOME/.kube/$TIER-k3s-kubeconfig"

./install-grafana-kuber.sh
./install-dockerconfigjson.sh

#./install-nginx.sh
#./install-nginx-internal.sh

./install-cert-manager.sh
./install-cluster-issuer.sh

#./install-morjoff-com-web-site.sh
#./install-hello-world.sh
#./install-hello-world-internal.sh
#./install-shadowsocks.sh
#./install-open-telemetry-test.sh
./install-inbucket.sh

#./install-ikev2-vpn.sh
