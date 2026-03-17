#!/usr/bin/env bash
# deploy-origin-rules.sh
#
# Configures Cloudflare Origin Rules for the cf-origin-rules.holden.xyz subdomain.
#
# Origin Rules use the Rulesets API (http_request_origin phase) to rewrite the
# destination host before the request reaches the origin. No code runs at the edge —
# the rule expression is evaluated by Cloudflare's ruleset engine.
#
# Routing logic:
#   /page/<odd>  → ORIGIN_ONE_HOST
#   /page/<even> → ORIGIN_TWO_HOST (0 is excluded via regex — no trailing zero-only match)
#
# Prerequisites:
#   - .env file with CLOUDFLARE_ZONE_ID, CLOUDFLARE_API_TOKEN
#   - ORIGIN_ONE_HOST and ORIGIN_TWO_HOST set below (workers.dev hostnames)
#   - jq installed (brew install jq)
#   - The cf-origin-rules.holden.xyz DNS record must be proxied through Cloudflare

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — update these after deploying the origin workers
# ---------------------------------------------------------------------------
ORIGIN_ONE_HOST="origin-one.spruce.workers.dev"
ORIGIN_TWO_HOST="origin-two.spruce.workers.dev"
SUBDOMAIN="cf-origin-rules.holden.xyz"

# ---------------------------------------------------------------------------
# Load env
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${CLOUDFLARE_ZONE_ID:?CLOUDFLARE_ZONE_ID is required}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required}"

CF_API="https://api.cloudflare.com/client/v4"
AUTH_HEADER="Authorization: Bearer $CLOUDFLARE_API_TOKEN"

# ---------------------------------------------------------------------------
# Step 1: Find existing http_request_origin phase ruleset for the zone
# ---------------------------------------------------------------------------
echo "Fetching zone rulesets..."
RULESETS=$(curl -s "$CF_API/zones/$CLOUDFLARE_ZONE_ID/rulesets" \
  -H "$AUTH_HEADER")

RULESET_ID=$(echo "$RULESETS" | jq -r '
  .result[] | select(.phase == "http_request_origin") | .id
')

# ---------------------------------------------------------------------------
# Step 2: Create the phase ruleset if it doesn't exist
# ---------------------------------------------------------------------------
if [[ -z "$RULESET_ID" ]]; then
  echo "No http_request_origin ruleset found — creating one..."
  CREATE_RESPONSE=$(curl -s -X POST "$CF_API/zones/$CLOUDFLARE_ZONE_ID/rulesets" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Origin Rules",
      "kind": "zone",
      "phase": "http_request_origin",
      "rules": []
    }')
  RULESET_ID=$(echo "$CREATE_RESPONSE" | jq -r '.result.id')
  echo "Created ruleset: $RULESET_ID"
else
  echo "Found existing ruleset: $RULESET_ID"
fi

# ---------------------------------------------------------------------------
# Step 3: PUT the full ruleset with our two routing rules
#
# Rule expressions:
#   Odd pages:  ends in 1,3,5,7,9
#   Even pages: ends in 2,4,6,8 (excludes /page/0 — no match for trailing 0
#               when the number itself is 0, since regex requires at least one
#               non-zero digit before the even suffix, or it must be a multi-
#               digit number ending in 0)
#
# Note: /page/10, /page/20 etc. (multi-digit ending in 0) ARE even and valid —
# the regex [0-9]+[02468] matches them. Only the literal "0" is excluded via
# the leading [1-9] requirement in the even rule.
# ---------------------------------------------------------------------------
echo "Updating origin rules..."

PUT_RESPONSE=$(curl -s -X PUT "$CF_API/zones/$CLOUDFLARE_ZONE_ID/rulesets/$RULESET_ID" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{
    \"rules\": [
      {
        \"description\": \"Route odd /page/:n to origin-one\",
        \"expression\": \"http.host eq \\\"$SUBDOMAIN\\\" and http.request.uri.path matches \\\"^/page/[0-9]*[13579]$\\\"\",
        \"action\": \"route\",
        \"action_parameters\": {
          \"host_header\": \"$ORIGIN_ONE_HOST\",
          \"origin\": {
            \"host\": \"$ORIGIN_ONE_HOST\"
          }
        },
        \"enabled\": true
      },
      {
        \"description\": \"Route even /page/:n to origin-two (excludes /page/0)\",
        \"expression\": \"http.host eq \\\"$SUBDOMAIN\\\" and http.request.uri.path matches \\\"^/page/[1-9][0-9]*[02468]$|^/page/[02468]$\\\"\",
        \"action\": \"route\",
        \"action_parameters\": {
          \"host_header\": \"$ORIGIN_TWO_HOST\",
          \"origin\": {
            \"host\": \"$ORIGIN_TWO_HOST\"
          }
        },
        \"enabled\": true
      }
    ]
  }")

SUCCESS=$(echo "$PUT_RESPONSE" | jq -r '.success')
if [[ "$SUCCESS" == "true" ]]; then
  echo "Origin rules deployed successfully."
else
  echo "Error deploying origin rules:"
  echo "$PUT_RESPONSE" | jq '.errors'
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 4: Add a Transform Rule to set x-forwarded-host before origin rewrite
#
# Uses http_request_late_transform phase (Modify Request Headers).
# Captures http.host before Origin Rules rewrites the Host header.
# ---------------------------------------------------------------------------
echo "Fetching transform rulesets..."
TRANSFORM_RULESETS=$(curl -s "$CF_API/zones/$CLOUDFLARE_ZONE_ID/rulesets" \
  -H "$AUTH_HEADER")

TRANSFORM_RULESET_ID=$(echo "$TRANSFORM_RULESETS" | jq -r '
  .result[] | select(.phase == "http_request_late_transform") | .id
')

if [[ -z "$TRANSFORM_RULESET_ID" ]]; then
  echo "No http_request_late_transform ruleset found — creating one..."
  CREATE_TRANSFORM=$(curl -s -X POST "$CF_API/zones/$CLOUDFLARE_ZONE_ID/rulesets" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Transform Rules",
      "kind": "zone",
      "phase": "http_request_late_transform",
      "rules": []
    }')
  TRANSFORM_RULESET_ID=$(echo "$CREATE_TRANSFORM" | jq -r '.result.id')
  echo "Created transform ruleset: $TRANSFORM_RULESET_ID"
else
  echo "Found existing transform ruleset: $TRANSFORM_RULESET_ID"
fi

echo "Setting x-forwarded-host transform rule..."
TRANSFORM_RESPONSE=$(curl -s -X PUT "$CF_API/zones/$CLOUDFLARE_ZONE_ID/rulesets/$TRANSFORM_RULESET_ID" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{
    \"rules\": [
      {
        \"description\": \"Set x-forwarded-host for cf-origin-rules subdomain\",
        \"expression\": \"http.host eq \\\"$SUBDOMAIN\\\"\",
        \"action\": \"rewrite\",
        \"action_parameters\": {
          \"headers\": {
            \"x-forwarded-host\": {
              \"operation\": \"set\",
              \"expression\": \"http.host\"
            }
          }
        },
        \"enabled\": true
      }
    ]
  }")

SUCCESS=$(echo "$TRANSFORM_RESPONSE" | jq -r '.success')
if [[ "$SUCCESS" == "true" ]]; then
  echo "Transform rule deployed successfully."
else
  echo "Error deploying transform rule:"
  echo "$TRANSFORM_RESPONSE" | jq '.errors'
  exit 1
fi
