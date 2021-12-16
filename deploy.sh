#!/bin/bash

set -euo pipefail

(cd terraform && terraform apply -auto-approve)
instance_ip=$(cd terraform && terraform output -raw ipv4_address)