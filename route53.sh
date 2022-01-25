#!/bin/bash
set -euo pipefail

(cd route53 && aws cloudformation deploy \
    --stack-name rss-hub-domain \
    --template-file cf.yml \
    --profile personal \
    --parameter-overrides IPAddress=1.1.1.1)
