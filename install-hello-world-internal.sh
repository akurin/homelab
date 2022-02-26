#!/bin/bash
set -euo pipefail

helm upgrade --install hello-world-internal  ./hello-world-internal
