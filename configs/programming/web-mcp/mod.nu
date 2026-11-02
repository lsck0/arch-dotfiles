use module.nu *

# web search and scraping for the agents: Perplexity and Firecrawl over their own APIs, each only with its key
export const SERVERS = {
    perplexity: {package: "@perplexity-ai/mcp-server@1.3.0", key: perplexity-api-key, env: PERPLEXITY_API_KEY}
    firecrawl: {package: "firecrawl-mcp@3.36.0", key: firecrawl-api-key, env: FIRECRAWL_API_KEY}
}

export def link [cfg: record] {
    let keys = $env.DOTFILES | path join configs secrets keys
    let usable = (profile-has secrets) and (which npx | is-not-empty)
    let wrapper = $nu.home-dir | path join .local bin web-mcp
    [
        (link-commands web-mcp.nu)
        (mcp-servers ($SERVERS | items {|name, s|
            let key = $keys | path join $s.key
            let spec = if $usable and (secret-is-plaintext $key) {
                {type: stdio, command: $wrapper, args: [$name]}
            } else {
                if $usable { log-warn $"no readable ($key), skipping ($name) \(README.md\)" }
                null
            }
            {name: $name, spec: $spec}
        } | reduce --fold {} {|r, acc| $acc | insert $r.name $r.spec }))
    ]
}
