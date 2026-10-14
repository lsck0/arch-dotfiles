# grafana

Claude's `grafana` MCP server: Grafana Labs' own
[mcp-grafana](https://github.com/grafana/mcp-grafana), the pinned release
binary in `~/.local/share/mcp-grafana`, stdio, read only (no write, admin or
docs tools, usage stats off). `grafana-mcp.nu` takes the url from the homelab
export (`~/projects/homelab/src/generated/lab.json`, `.monitoring.grafana`)
and the token from secrets at each start.

## Setup

The server needs a Grafana service account token, which lives in the private
secrets submodule. `mod.nu` registers nothing while the file is missing.

```
# secrets/grafana-mcp-token
glsa_...
```

Create it in Grafana under Administration, Service accounts: one account
`claude` with role Viewer, one token, no expiry or a rotation you keep.

The homelab Grafana sits behind Authelia forwardauth on the ingress and trusts
`Remote-User` from the ingress and its own loopback only, so a bearer token
sent to `https://grafana.lsck0.dev` is redirected to the SSO portal before
Grafana sees it. The token works once the homelab lets it through: an
Authelia rule that passes requests carrying `Authorization: Bearer glsa_...`
to Grafana's api, or a desktop-reachable Grafana port.

## Checking

```bash
claude mcp list | grep grafana
npx -y @modelcontextprotocol/inspector@0.17.2 --cli grafana-mcp --method tools/list
```
