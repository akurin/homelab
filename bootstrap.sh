#!/bin/bash
set -euo pipefail

./terraform-apply.sh

./install-k3s.sh

chmod 600 ~/.kube/k3s-kubeconfig
export KUBECONFIG=~/.kube/k3s-kubeconfig

./install-nginx.sh
./install-nginx-internal.sh
./install-cert-manager.sh
./install-cluster-issuer.sh

./install-grafana-kuber.sh
./install-morjoff-com-web-site.sh
./install-hello-world.sh
./install-hello-world-internal.sh
./install-shadowsocks.sh
./install-open-telemetry-test.sh
