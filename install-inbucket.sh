#!/bin/bash
set -euo pipefail

helm upgrade --install inbucket ./inbucket/helm-charts/inbucket
