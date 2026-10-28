#!/usr/bin/env bash
# Delete everything (WAF, API, Lambda, DynamoDB, Cognito, alarms, dashboard).
# Usage: ./scripts/cleanup.sh [region]
set -euo pipefail
REGION="${1:-${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-west-1}}}"
STACK="${STACK_NAME:-todo-api}"
aws cloudformation delete-stack --stack-name "$STACK" --region "$REGION"
aws cloudformation wait stack-delete-complete --stack-name "$STACK" --region "$REGION"
echo "Stack $STACK deleted."
