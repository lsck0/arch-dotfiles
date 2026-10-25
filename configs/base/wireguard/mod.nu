use module.nu *

export const meta = {packages: {pacman: [openvpn wireguard-tools]}, volatile: true}

const CONF = "/etc/wireguard/wg0.conf"
const SECRET_NAME = '^[A-Za-z0-9._-]+$'

# The admin's wg0.conf from the secrets, data only: wg-quick runs the *Up/*Down hooks as root and SaveConfig
# would write back into it. A run whose secret is absent (locked, not pulled) declares the placed copy as it
# is, so it stays; no WIREGUARD name declares nothing, and a copy dot placed goes as no longer declared.
export def system [cfg: record] {
    let name = $env.WIREGUARD? | default ""
    if $name == "" { return [] }
    if not ($name =~ $SECRET_NAME) {
        error make {msg: $"wireguard: '($name)' is not a secrets file name"}
    }
    let secret = $env.DOTFILES_SECRETS? | default "/nonexistent" | path join $name
    let text = if ($secret | path exists) { open --raw $secret } else if ($CONF | path exists) { open --raw $CONF } else { return [] }
    if not ($text =~ '(?m)^\[Interface\]') or ($text =~ '(?im)^\s*(PreUp|PostUp|PreDown|PostDown|SaveConfig)\s*=') {
        error make {msg: $"wireguard: ($name) is no [Interface] config or carries hooks/SaveConfig, keeping ($CONF)"}
    }
    [(file-text $CONF $text --mode "600")]
}
