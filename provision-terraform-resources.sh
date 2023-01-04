#!/bin/bash
set -euo pipefail

(cd terraform-resources && VULTR_API_KEY="$(pass vultr/apikey)" terraform apply)
