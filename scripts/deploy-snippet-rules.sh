#!/usr/bin/env bash
# deploy-snippet-rules.sh
#
# Configures a Cloudflare Snippet for the cf-snippet-rules.holden.xyz subdomain.
#
# Snippets are lightweight JavaScript that run on Cloudflare's edge before the
# request reaches the origin. Unlike full Workers, Snippets are configured per-zone
# via the dashboard or API and are attached to rules via expressions.
#
# This script:
#   1. Uploads the snippet JS code to the zone
#   2. Links the snippet to a rule matching cf-snippet-rules.holden.xyz
#
# Routing logic (inside the snippet):
#   /page/<odd>  → ORIGIN_ONE_HOST
#   /page/<even> → ORIGIN_TWO_HOST (0 excluded)
#   anything else → passes through (will 404 at origin if no route matches)
#
# Prerequisites:
#   - .env file with CLOUDFLARE_ZONE_ID, CLOUDFLARE_API_TOKEN
#   - ORIGIN_ONE_HOST and ORIGIN_TWO_HOST set below (workers.dev hostnames)
#   - The cf-snippet-rules.holden.xyz DNS record must be proxied through Cloudflare

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — update these after deploying the origin workers
# ---------------------------------------------------------------------------
ORIGIN_ONE_HOST="origin-one.holden.xyz"
ORIGIN_TWO_HOST="origin-two.holden.xyz"
SUBDOMAIN="cf-snippet-rules.holden.xyz"
SNIPPET_NAME="routing_snippet"

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
# Step 1: Write the snippet JS to a temp file
# ---------------------------------------------------------------------------
SNIPPET_FILE=$(mktemp /tmp/routing_snippet_XXXXXX.js)
trap 'rm -f "$SNIPPET_FILE"' EXIT

cat > "$SNIPPET_FILE" <<SNIPPET_EOF
// Cloudflare Snippet: routing_snippet
// Routes /page/:n traffic to origin-one (odd) or origin-two (even).
// Any other path returns 404.

const ORIGIN_ONE_HOST = "$ORIGIN_ONE_HOST";
const ORIGIN_TWO_HOST = "$ORIGIN_TWO_HOST";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/page\/(\d+)$/);

    if (!match) {
      return new Response("Not Found", { status: 404 });
    }

    const page_number = parseInt(match[1], 10);
    if (page_number === 0) {
      return new Response("Not Found", { status: 404 });
    }

    const origin_host =
      page_number % 2 !== 0 ? ORIGIN_ONE_HOST : ORIGIN_TWO_HOST;

    const headers = new Headers(request.headers);
    headers.set("x-forwarded-host", url.hostname);

    const client_ip = request.headers.get("CF-Connecting-IP");
    if (client_ip) {
      headers.set("X-Real-IP", client_ip);
      headers.set("X-Forwarded-For", client_ip);
    }

    const origin_url = new URL(url.pathname, \`https://\${origin_host}\`);

    return fetch(origin_url.toString(), { method: request.method, headers, cf: { resolveOverride: url.hostname } });
  },
};
SNIPPET_EOF

# ---------------------------------------------------------------------------
# Step 2: Upload the snippet via multipart PUT
# ---------------------------------------------------------------------------
echo "Uploading snippet '$SNIPPET_NAME'..."

UPLOAD_RESPONSE=$(curl -s -X PUT \
  "$CF_API/zones/$CLOUDFLARE_ZONE_ID/snippets/$SNIPPET_NAME" \
  -H "$AUTH_HEADER" \
  -F "files=@$SNIPPET_FILE;filename=snippet.js" \
  -F 'metadata={"main_module":"snippet.js"}')

SUCCESS=$(echo "$UPLOAD_RESPONSE" | jq -r '.success')
if [[ "$SUCCESS" != "true" ]]; then
  echo "Error uploading snippet:"
  echo "$UPLOAD_RESPONSE" | jq '.errors'
  exit 1
fi
echo "Snippet uploaded."

# ---------------------------------------------------------------------------
# Step 3: Link the snippet to a rule
#
# The PUT to snippet_rules replaces ALL existing snippet rules for the zone.
# If you have other snippets, list them first and include them here too.
# ---------------------------------------------------------------------------
echo "Linking snippet to rule for $SUBDOMAIN..."

RULES_RESPONSE=$(curl -s -X PUT \
  "$CF_API/zones/$CLOUDFLARE_ZONE_ID/snippets/snippet_rules" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{
    \"rules\": [
      {
        \"description\": \"Run routing_snippet for cf-snippet-rules subdomain\",
        \"enabled\": true,
        \"expression\": \"http.host eq \\\"$SUBDOMAIN\\\"\",
        \"snippet_name\": \"$SNIPPET_NAME\"
      }
    ]
  }")

SUCCESS=$(echo "$RULES_RESPONSE" | jq -r '.success')
if [[ "$SUCCESS" == "true" ]]; then
  echo "Snippet rules deployed successfully."
else
  echo "Error deploying snippet rules:"
  echo "$RULES_RESPONSE" | jq '.errors'
  exit 1
fi
