use module.nu *

const CHROMIUM = "/usr/bin/chromium"
const FIREFOX = "/usr/bin/firefox"

# the browsers come from desktop/chromium and desktop/firefox: a server is only registered when its browser exists
export const meta = {packages: {pacman: [chrome-devtools-mcp playwright-mcp]}, inputs: [$CHROMIUM $FIREFOX]}

export const options = {
    headless: {type: bool, default: true, doc: "The agents' browsers run without a window", label: "Headless browsers"}
}

def playwright [browser: string, exe: string, out: path, headless: list<string>]: nothing -> record {
    {
        type: stdio command: playwright-mcp
        args: [--browser $browser --executable-path $exe ...$headless --isolated --output-dir $out --file-paths absolute]
    }
}

export def link [cfg: record] {
    let out = xdg cache playwright-mcp
    let has_chromium = $CHROMIUM | path exists
    let headless = if $cfg.headless { [--headless] } else { [] }
    mcp-servers {
        playwright: (if $has_chromium { playwright chromium $CHROMIUM $out $headless | update args { append "--sandbox" } })
        playwright-firefox: (if ($FIREFOX | path exists) { playwright moz-firefox $FIREFOX $out $headless })
        chrome-devtools: (if $has_chromium {
            {
                type: stdio command: chrome-devtools-mcp
                args: [--executablePath $CHROMIUM ...$headless --isolated --no-usage-statistics --no-performance-crux]
                env: {CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS: "1"}
            }
        })
    }
}
