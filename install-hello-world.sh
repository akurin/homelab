#!/bin/bash
set -euo pipefail

helm upgrade --install hello-world ./hello-world
