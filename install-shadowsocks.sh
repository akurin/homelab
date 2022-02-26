#!/bin/bash
set -euo pipefail

helm upgrade \
    --install shadowsocks predatorray/shadowsocks \
    --set service.type=NodePort \
    --set shadowsocks.password.plainText="$(openssl rand -base64 12)"

NODE_SS_PORT=$(kubectl get --namespace default -o jsonpath="{.spec.ports[?(@.name=='ss-tcp')].nodePort}" services shadowsocks)
NODE_IP=$(kubectl get nodes --namespace default -o jsonpath="{.items[0].status.addresses[0].address}")
echo "Shadowsocks endpoint: ss://$NODE_IP:$NODE_SS_PORT"
echo "Password: $(helm get values shadowsocks -o json | jq .shadowsocks.password.plainText -r)"
