# web-mcp

Web search for the agents: the `searxng` MCP server (`mcp-searxng`, pinned in `mod.nu`) against the homelab's
`https://search.<domain>`, which answers JSON to luca-pc, luca-notebook and wireguard without a login or rate limit.
No key, no paid API. Registered only with the `homelab` platform fact. The earlier Perplexity and Firecrawl servers are
dropped from every agent's config.

Check: `curl -s -H 'Accept: application/json' 'https://search.lsck0.dev/search?q=test&format=json' | jq '.results | length'`.
