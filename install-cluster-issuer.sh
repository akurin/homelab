#!/bin/bash
set -euo pipefail

helm upgrade --install --atomic cluster-issuer cluster-issuer
