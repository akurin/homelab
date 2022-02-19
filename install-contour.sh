#!/bin/bash
set -euo pipefail

facts=$(cd ansible && ANSIBLE_LOAD_CALLBACK_PLUGINS=true ANSIBLE_STDOUT_CALLBACK=json ansible all -m setup)
internalIP=$(echo $facts | jq -r .plays[0].tasks[0].hosts.node_0.ansible_facts.ansible_tailscale0.ipv4.address)
externalIP=$(echo $facts | jq -r .plays[0].tasks[0].hosts.node_0.ansible_facts.ansible_enp1s0.ipv4.address)

helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade \
    --install contour-external bitnami/contour \
    --namespace kube-system \
    -f contour/external.yaml \
    --set envoy.hostIPs.http=$externalIP \
    --set envoy.hostIPs.https=$externalIP
helm install \
    contour-internal bitnami/contour \
    --namespace kube-system \
    -f contour/internal.yaml \
    --set envoy.hostIPs.http=$internalIP \
    --set envoy.hostIPs.https=$internalIP
