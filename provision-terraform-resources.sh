#!/bin/bash
set -euo pipefail

(cd terraform-resources && terraform apply)
