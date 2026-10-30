use module.nu *

# the browsers come from desktop/chromium and desktop/firefox: a server is only registered when its browser exists
export const meta = {packages: {pacman: [chrome-devtools-mcp playwright-mcp]}, inputs: [/usr/bin/chromium /usr/bin/firefox]}

const CHROMIUM = "/usr/bin/chromium"
const FIREFOX = "/usr/bin/firefox"

def playwright [browser: string, exe: string, out: path]: nothing -> record {
    {
        type: stdio command: playwright-mcp env: {}
        args: [--browser $browser --executable-path $exe --headless --isolated --output-dir $out --file-paths absolute]
    }
}

export def link [cfg: record] {
    let out = xdg cache playwright-mcp
    let has_chromium = $CHROMIUM | path exists
    mcp-servers {
        playwright: (if $has_chromium { playwright chromium $CHROMIUM $out | update args { append "--sandbox" } })
        playwright-firefox: (if ($FIREFOX | path exists) { playwright moz-firefox $FIREFOX $out })
        chrome-devtools: (if $has_chromium {
            {
                type: stdio command: chrome-devtools-mcp
                args: [--executablePath $CHROMIUM --headless --isolated --no-usage-statistics --no-performance-crux]
                env: {CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS: "1"}
            }
        })
    }
}
