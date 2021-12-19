#!/bin/bash
set -euo pipefail

(cd terraform && terraform apply)
