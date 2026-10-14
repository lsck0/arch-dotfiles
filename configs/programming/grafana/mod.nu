use module.nu *

export const meta = {packages: {pacman: [grafana-alloy loki]}}

# a tag can be re-uploaded, so the tarball is pinned by content; bump both together
const VERSION = "2.0.2"
const SHA256 = "624e997b78bcadf236f82f8086827890ba77b6dfdc6fd6446f7c48dfd9e586f0"
const URL = $"https://github.com/grafana/mcp-grafana/releases/download/v($VERSION)/mcp-grafana_Linux_x86_64.tar.gz"

# the launcher reads url and token at each start, so neither lands in ~/.claude.json
export def link [cfg: record] {
    let claude = $nu.home-dir | path join .claude.json
    let token = $env.DOTFILES | path join secrets grafana-mcp-token
    if not (profile-has homelab) or not (secret-is-plaintext $token) {
        if (profile-has homelab) { log-warn $"no readable ($token), skipping \(README.md\)" }
        return (json-merge $claude [(json-delete [mcpServers grafana])])
    }
    let dest = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join mcp-grafana mcp-grafana
    [
        (fetch-file $URL $SHA256 $dest --mode 755 --extract mcp-grafana)
        (link-commands grafana-mcp.nu)
        (json-merge $claude [(json-set [mcpServers grafana] {type: stdio, command: ($nu.home-dir | path join .local bin grafana-mcp), args: []})])
    ]
}
