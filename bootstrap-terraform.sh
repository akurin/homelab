#!/bin/bash
set -euo pipefail

aws cloudformation deploy --stack-name terraform-state-backend --template-file terraform-bootstrap/cf.yaml --capabilities CAPABILITY_IAM --profile personal
