#!/bin/bash
set -euo pipefail

helm upgrade --install rss-bridge  ./rss-bridge
