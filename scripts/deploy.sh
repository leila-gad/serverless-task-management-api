#!/usr/bin/env bash
# Build and deploy the stack. Usage: ./scripts/deploy.sh [region] [alert-email]
set -euo pipefail
cd "$(dirname "$0")/.."

REGION="${1:-${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-west-1}}}"
EMAIL="${2:-}"
STACK="${STACK_NAME:-todo-api}"

sam build
sam deploy \
  --stack-name "$STACK" \
  --region "$REGION" \
  --resolve-s3 \
  --capabilities CAPABILITY_IAM \
  --no-confirm-changeset \
  --no-fail-on-empty-changeset \
  --parameter-overrides "AlertEmail=${EMAIL}"

echo
aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table
