# Project Brief

> Original prompt that defined this project.

---

this project will be used to test routing methods with Cloudflare. I will need two simple web servers (cloudflare workers, typescript) that reply to requests with a simple text string "Hello from (server name), request-id: abc123" where server name is the name of the web server, and request ID is a random UUID. Both servers run on separate workers, so they are isolated and have different domains. we'll then need to configure the subdomains for https://*.holden.xyz such as `cf-origin-rules` and `cf-snippet-rules` and `cf-worker-rules` so we can test 3 different setups where we change the host based on the url route. `/page/1` will go to web server A, and `/page/2` will go to server B (even/odd split). the project needs a README, two cloudflare workers in typescript for the web servers, another worker for the `cf-worker-rules` subdomain setup, and configs for the other two than can be applied with the cloudflare api via CLI.

## Clarifications

- Origin workers named `origin-one` (server A) and `origin-two` (server B)
- Even/odd routing: odd page numbers → origin-one, even → origin-two
- `/page/0`, `/page/abc`, `/`, and all non-`/page/:n` paths → 404
- Origin workers deployed to default `*.workers.dev` domains
- Three routing setups on subdomains of `holden.xyz`:
  - `cf-origin-rules.holden.xyz` — Cloudflare Origin Rules (Rulesets API, no code at edge)
  - `cf-snippet-rules.holden.xyz` — Cloudflare Snippets (lightweight JS at edge)
  - `cf-worker-rules.holden.xyz` — Cloudflare Worker reverse proxy/router
- Shell scripts with `curl` for Origin Rules and Snippets configuration
- Env vars for zone ID, account ID, API token
- pnpm monorepo, strict TypeScript, separate `wrangler.toml` per worker
- Regex support assumed available for Origin Rules expressions (Business/Enterprise plan)
