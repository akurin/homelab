#!/bin/bash
set -euo pipefail

helm upgrade \
    --install cluster-issuer cluster-issuer
