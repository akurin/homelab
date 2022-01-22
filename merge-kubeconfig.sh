#!/bin/bash
set -euo pipefail

cp ~/.kube/config ~/.kube/config.bak && KUBECONFIG=~/.kube/config:~/.kube/microk8s-kubeconfig kubectl config view --flatten > /tmp/config && mv /tmp/config ~/.kube/config
chmod 600 ~/.kube/config
