#!/bin/bash
set -euo pipefail

helm upgrade --install --rollback-on-failure cluster-issuer cluster-issuer
