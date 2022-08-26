#!/bin/bash
set -euo pipefail

helm upgrade --install open-telemetry-test ./open-telemetry-test
