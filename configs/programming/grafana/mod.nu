use module.nu *

export const meta = {packages: {pacman: [grafana-alloy loki]}}

const VERSION = "2.0.2"
const SHA256 = "624e997b78bcadf236f82f8086827890ba77b6dfdc6fd6446f7c48dfd9e586f0"
const URL = $"https://github.com/grafana/mcp-grafana/releases/download/v($VERSION)/mcp-grafana_Linux_x86_64.tar.gz"

export def link [cfg: record] {
    let token = $env.DOTFILES | path join configs secrets keys grafana-mcp-token
    let wanted = (profile-has secrets) and (platform-has homelab)
    if not $wanted or not (secret-is-plaintext $token) {
        if $wanted { log-warn $"no readable ($token), skipping \(README.md\)" }
        return (mcp-servers {grafana: null})
    }
    let dest = xdg data mcp-grafana mcp-grafana
    [
        (fetch-file $URL $SHA256 $dest --mode 755 --extract mcp-grafana)
        (link-commands grafana-mcp.nu)
        (mcp-servers {grafana: {type: stdio, command: ($nu.home-dir | path join .local bin grafana-mcp), args: []}})
    ]
}
