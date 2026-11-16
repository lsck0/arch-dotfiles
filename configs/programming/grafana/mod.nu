use module.nu *

const VERSION = "2.2.0"
const SHA256 = "f93bfbd94cde68cc2e43cf5ba55da4f8e28b1a36b14fb14dadd566fc36b1312b" # released 2026-11-02
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
        (mcp-command grafana grafana-mcp.nu)
    ]
}
