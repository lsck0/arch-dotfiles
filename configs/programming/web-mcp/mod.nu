use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# Web search for the agents through the homelab's searxng: no API key, no paid service, results from the house's own
# engine. Only on a machine with the homelab fact; the lab passes luca-pc's and luca-notebook's addresses and the
# wireguard subnet through its limiter. mcp-searxng and its dependencies are pinned by config/mcp/package-lock.json.

export def link [cfg: record] {
    let prefix = xdg data web-mcp
    let node_modules = $prefix | path join node_modules
    let wanted = (platform-has homelab) and (which npm | is-not-empty)
    let searxng = if $wanted {
        {
            type: stdio, command: ($node_modules | path join .bin mcp-searxng), args: []
            env: {SEARXNG_URL: $"https://search.($HOMELAB.domain)", DO_NOT_TRACK: "1"}
        }
    }
    [
        (if $wanted { mcp-npm web-mcp config/mcp $prefix })
        (mcp-servers {searxng: $searxng})
    ]
}
