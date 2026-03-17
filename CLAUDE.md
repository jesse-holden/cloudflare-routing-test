# Claude Code — Project Instructions

## What this project is

A test bench for comparing three Cloudflare routing methods. Two origin Workers serve
traffic; three subdomains of `holden.xyz` each use a different method to route
`/page/:n` by even/odd parity to the correct origin.

## Structure

```
workers/origin-one/   — Origin Worker A (odd pages)
workers/origin-two/   — Origin Worker B (even pages)
workers/router/       — Reverse-proxy Worker for cf-worker-rules.holden.xyz
scripts/              — Shell scripts to configure Origin Rules and Snippets via API
```

## Key rules

- **pnpm** workspace — run installs from the repo root.
- All workers use **strict TypeScript** (`tsconfig.base.json` at root).
- Worker dependencies (`wrangler`, `@cloudflare/workers-types`) live in each worker's
  own `package.json`, not the root.

## Deployment order

1. Deploy origin workers first: `pnpm run deploy:origins`
   - Note the `*.workers.dev` URLs printed by wrangler.
2. Update `ORIGIN_ONE_HOST` / `ORIGIN_TWO_HOST` in:
   - `workers/router/wrangler.toml` → `[vars]`
   - `scripts/deploy-origin-rules.sh` → top of file
   - `scripts/deploy-snippet-rules.sh` → top of file
3. Deploy the router worker: `pnpm run deploy:router`
4. Set up DNS — create proxied CNAME records for all three subdomains pointing at
   the router worker (or any placeholder origin for Origin Rules / Snippets setups).
5. Run `scripts/deploy-origin-rules.sh` and `scripts/deploy-snippet-rules.sh`.

## Environment variables

Copy `.env.example` → `.env` and fill in:

```
CLOUDFLARE_ZONE_ID=      # Zone ID for holden.xyz (Cloudflare dashboard → Overview)
CLOUDFLARE_ACCOUNT_ID=   # Account ID (Cloudflare dashboard → right sidebar)
CLOUDFLARE_API_TOKEN=    # Token with Zone:Edit + Origin Rules:Edit + Snippets:Write
```

## Routing logic (all three methods)

| Path         | Destination  |
|--------------|--------------|
| `/page/1`    | origin-one   |
| `/page/2`    | origin-two   |
| `/page/3`    | origin-one   |
| `/page/10`   | origin-two   |
| `/page/0`    | 404          |
| `/page/abc`  | 404          |
| `/`          | 404          |

## Scripts

Both scripts require `jq`. Install with `brew install jq`.

The Snippets script (`deploy-snippet-rules.sh`) replaces **all** snippet rules for
the zone on each run. If you have other snippets on the zone, extend the `rules`
array in that script.
