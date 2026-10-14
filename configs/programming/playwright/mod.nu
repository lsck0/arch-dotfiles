use module.nu *

export const meta = {packages: {pacman: [chrome-devtools-mcp playwright-mcp]}}

const CHROMIUM = "/usr/bin/chromium"

def playwright [browser: string, exe: string, out: path]: nothing -> record {
    {
        type: stdio command: playwright-mcp env: {}
        args: [--browser $browser --executable-path $exe --headless --isolated --output-dir $out --file-paths absolute]
    }
}

# playwright-mcp headless on a throwaway profile (chromium, and firefox over webdriver bidi), output in the cache;
# chrome-devtools-mcp debugs in a visible chromium on its own profile, google's usage stats and crux lookups off.
# base/apparmor's local/chromium and local/firefox allow these profile dirs
export def link [cfg: record] {
    let out = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join playwright-mcp
    let chromium = playwright chromium $CHROMIUM $out
    json-merge ($nu.home-dir | path join .claude.json) [
        (json-set [mcpServers playwright] ($chromium | update args { append "--sandbox" }))
        (json-set [mcpServers playwright-firefox] (playwright moz-firefox /usr/bin/firefox $out))
        (json-set [mcpServers chrome-devtools] {
            type: stdio command: chrome-devtools-mcp
            args: [--executablePath $CHROMIUM --no-usage-statistics --no-performance-crux]
            env: {CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS: "1"}
        })
    ]
}
