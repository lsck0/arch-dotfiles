# grafana

Claude's `grafana` MCP server: pinned [mcp-grafana](https://github.com/grafana/mcp-grafana), stdio, read only.
`grafana-mcp.nu` reads the url from the homelab's `lab.json` (`.monitoring.grafana`) and the token from secrets.

Setup: a Grafana service account `claude` with role Viewer; its token in `configs/secrets/keys/grafana-mcp-token`.
Without the file nothing is registered.

Gotcha: grafana.lsck0.dev sits behind Authelia, so a bearer token is redirected to SSO until the homelab lets
`Authorization: Bearer glsa_...` through to the API.

Check: `claude mcp list | grep grafana`.
