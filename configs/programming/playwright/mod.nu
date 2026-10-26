use module.nu *

export const meta = {packages: {pacman: [chrome-devtools-mcp playwright-mcp]}}

const CHROMIUM = "/usr/bin/chromium"

def playwright [browser: string, exe: string, out: path]: nothing -> record {
    {
        type: stdio command: playwright-mcp env: {}
        args: [--browser $browser --executable-path $exe --headless --isolated --output-dir $out --file-paths absolute]
    }
}

export def link [cfg: record] {
    let out = xdg cache playwright-mcp
    let chromium = playwright chromium $CHROMIUM $out
    mcp-servers {
        playwright: ($chromium | update args { append "--sandbox" })
        playwright-firefox: (playwright moz-firefox /usr/bin/firefox $out)
        chrome-devtools: {
            type: stdio command: chrome-devtools-mcp
            args: [--executablePath $CHROMIUM --no-usage-statistics --no-performance-crux]
            env: {CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS: "1"}
        }
    }
}
