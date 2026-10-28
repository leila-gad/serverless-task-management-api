#!/usr/bin/env bash
# Sends many unauthenticated requests from this IP to trigger the WAF rate-based rule.
# Once the limit is exceeded, WAF starts answering 403 instead of the API's 401.
# Note: WAF rate evaluation is not instant; it can take a minute or two to kick in.
# Usage: ./scripts/waf_rate_test.sh [region] [requests]
set -euo pipefail
REGION="${1:-${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-west-1}}}"
N="${2:-300}"
STACK="${STACK_NAME:-todo-api}"
API="$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
      --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)"

for i in $(seq 1 "$N"); do
  curl -s -o /dev/null -w "%{http_code}\n" "$API/todos"
done | sort | uniq -c
echo "401 = reached API Gateway (no token); 403 = blocked by WAF; 429 = API Gateway throttling."
