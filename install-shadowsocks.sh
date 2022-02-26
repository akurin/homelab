#!/bin/bash
set -euo pipefail

helm upgrade \
    --install shadowsocks predatorray/shadowsocks \
    --set service.type=NodePort \
    --set shadowsocks.password.plainText="$(openssl rand -base64 12)"
