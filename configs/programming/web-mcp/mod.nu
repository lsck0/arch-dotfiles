use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# Web search for the agents through the homelab's searxng: no API key, no paid service, results from the house's own
# engine. Only on a machine with the homelab fact; the lab passes luca-pc's and luca-notebook's addresses and the
# wireguard subnet through its limiter. mcp-searxng and its dependencies are pinned by mcp/package-lock.json.
const HERE = path self .
const LOCK_KEY_LENGTH = 16
# the paid servers this module registered before searxng; null drops them from every agent
const RETIRED = [perplexity firecrawl]

export def link [cfg: record] {
    let prefix = xdg data web-mcp
    let lock = $HERE | path join mcp package-lock.json
    let node_modules = $prefix | path join node_modules
    let wanted = (platform-has homelab) and (which npm | is-not-empty)
    let searxng = if $wanted {
        {
            type: stdio, command: ($node_modules | path join .bin mcp-searxng), args: []
            env: {SEARXNG_URL: $"https://search.($HOMELAB.domain)", DO_NOT_TRACK: "1"}
        }
    }
    [
        (if $wanted {
            [
                (file-copy ($HERE | path join mcp package.json) ($prefix | path join package.json))
                (file-copy $lock ($prefix | path join package-lock.json))
                (exec web-mcp-install [npm ci --no-audit --no-fund --prefix $prefix] --creates $node_modules
                    --key (open --raw $lock | hash sha256 | str substring 0..<($LOCK_KEY_LENGTH))
                    --undo [rm -rf $node_modules] --network)
            ]
        })
        (mcp-servers ($RETIRED | each {|name| {$name: null} } | into record | merge {searxng: $searxng}))
    ]
}
