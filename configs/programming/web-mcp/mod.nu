use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# Web search for the agents through the homelab's searxng: no API key, no paid service, results from the house's own
# engine. Only on a machine with the homelab fact; the lab passes luca-pc's and luca-notebook's addresses and the
# wireguard subnet through its limiter.
const SEARXNG_PACKAGE = "mcp-searxng@2.8.1"
# the paid servers this module registered before searxng; null drops them from every agent
const RETIRED = [perplexity firecrawl]

export def link [cfg: record] {
    let searxng = if (platform-has homelab) and (which npx | is-not-empty) {
        {
            type: stdio, command: npx, args: [-y $SEARXNG_PACKAGE]
            env: {SEARXNG_URL: $"https://search.($HOMELAB.domain)", DO_NOT_TRACK: "1"}
        }
    }
    [(mcp-servers ($RETIRED | each {|name| {$name: null} } | into record | merge {searxng: $searxng}))]
}
