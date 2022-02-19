#!/bin/bash
set -euo pipefail

helm upgrade \
    --install contour-crd contour-crd \
    --namespace kube-system
