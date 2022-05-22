#!/bin/bash
set -euo pipefail

helm upgrade --install morjoff-com-web-site  ./morjoff-com-web-site/helm
