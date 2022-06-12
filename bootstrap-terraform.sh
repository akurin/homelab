#!/bin/bash
set -euo pipefail

aws cloudformation deploy \
    --stack-name terraform-state-backend \
    --template-file terraform-s3-backend-bootstrap/cf.yaml \
    --capabilities CAPABILITY_IAM \
    --profile personal

TerraformStateS3BucketName=$(aws cloudformation describe-stacks \
    --stack-name terraform-state-backend \
    --output text \
    --query "Stacks[0].Outputs[?OutputKey=='TerraformStateS3BucketName'].OutputValue" \
    --profile personal)

TerraformStateLockDynamoDBTableName=$(aws cloudformation describe-stacks \
    --stack-name terraform-state-backend \
    --output text \
    --query "Stacks[0].Outputs[?OutputKey=='TerraformStateLockDynamoDBTableName'].OutputValue" \
    --profile personal)

(
    cd terraform-resources &&
    terraform init \
        -backend-config="bucket=$TerraformStateS3BucketName" \
        -backend-config="dynamodb_table=$TerraformStateLockDynamoDBTableName"
)
