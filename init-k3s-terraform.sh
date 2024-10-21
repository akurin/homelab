#!/bin/bash
set -euo pipefail

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
	cd k3s-terraform-resources &&
		terraform init \
			--upgrade \
			-backend-config="bucket=$TerraformStateS3BucketName" \
			-backend-config="dynamodb_table=$TerraformStateLockDynamoDBTableName"
)
