#!/usr/bin/env bash
# End-to-end test against the deployed stack:
#   no token -> 401, then create user, sign in, full CRUD with the JWT.
# Usage: ./scripts/smoke_test.sh [region]
set -euo pipefail

REGION="${1:-${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-west-1}}}"
STACK="${STACK_NAME:-todo-api}"
EMAIL="${TEST_EMAIL:-demo.user@example.com}"
PASSWORD="${TEST_PASSWORD:-DemoPassw0rd}"

out() { aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

API="$(out ApiUrl)"; POOL="$(out UserPoolId)"; CLIENT="$(out UserPoolClientId)"
echo "API: $API"

echo; echo "1) Request WITHOUT token (expect 401)"
curl -s -o /dev/null -w "HTTP %{http_code}\n" "$API/todos"

echo; echo "2) Create test user (ignored if it already exists) and sign in"
aws cognito-idp admin-create-user --region "$REGION" --user-pool-id "$POOL" \
  --username "$EMAIL" --message-action SUPPRESS >/dev/null 2>&1 || true
aws cognito-idp admin-set-user-password --region "$REGION" --user-pool-id "$POOL" \
  --username "$EMAIL" --password "$PASSWORD" --permanent
TOKEN="$(aws cognito-idp initiate-auth --region "$REGION" --client-id "$CLIENT" \
  --auth-flow USER_PASSWORD_AUTH --auth-parameters "USERNAME=$EMAIL,PASSWORD=$PASSWORD" \
  --query 'AuthenticationResult.IdToken' --output text)"
AUTH=(-H "Authorization: $TOKEN" -H "Content-Type: application/json")

echo; echo "3) POST /todos"
CREATED="$(curl -s "${AUTH[@]}" -X POST "$API/todos" -d '{"title":"Deploy the project"}')"
echo "$CREATED"
ID="$(echo "$CREATED" | python3 -c 'import sys,json; print(json.load(sys.stdin)["todoId"])')"

echo; echo "4) GET /todos"
curl -s "${AUTH[@]}" "$API/todos"; echo

echo; echo "5) GET /todos/$ID"
curl -s "${AUTH[@]}" "$API/todos/$ID"; echo

echo; echo "6) PUT /todos/$ID (mark done)"
curl -s "${AUTH[@]}" -X PUT "$API/todos/$ID" -d '{"status":"done"}'; echo

echo; echo "7) GET /todos?status=done"
curl -s "${AUTH[@]}" "$API/todos?status=done"; echo

echo; echo "8) Validation error (expect 400)"
curl -s -w "\nHTTP %{http_code}\n" "${AUTH[@]}" -X POST "$API/todos" -d '{"title":""}'

echo; echo "9) DELETE /todos/$ID (expect 204), then GET (expect 404)"
curl -s -o /dev/null -w "DELETE HTTP %{http_code}\n" "${AUTH[@]}" -X DELETE "$API/todos/$ID"
curl -s -o /dev/null -w "GET    HTTP %{http_code}\n" "${AUTH[@]}" "$API/todos/$ID"
echo; echo "Smoke test finished."
