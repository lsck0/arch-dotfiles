use module.nu *
use converge.nu [state-read]

export const meta = {packages: {pacman: [openvpn wireguard-tools]}, volatile: true}

const CONF = "/etc/wireguard/wg0.conf"
const SECRET_NAME = '^[A-Za-z0-9._-]+$'

# The admin's wg0.conf from the secrets, data only (wg-quick runs its *Up/*Down hooks as root). With the secret
# absent (locked) dot's own unchanged copy is declared again; a hand-made or edited one is never taken over.
export def system [cfg: record] {
    let name = $env.WIREGUARD? | default ""
    if $name == "" { return [] }
    if not ($name =~ $SECRET_NAME) {
        error make {msg: $"wireguard: '($name)' is not a secrets file name"}
    }
    let secret = $env.DOTFILES_SECRETS? | default "/nonexistent" | path join $name
    let text = if ($secret | path exists) { open --raw $secret } else if (placed-unchanged) { open --raw $CONF } else { return [] }
    if not ($text =~ '(?m)^\[Interface\]') or ($text =~ '(?im)^\s*(PreUp|PostUp|PreDown|PostDown|SaveConfig)\s*=') {
        error make {msg: $"wireguard: ($name) is no [Interface] config or carries hooks/SaveConfig, keeping ($CONF)"}
    }
    [(file-text $CONF $text --mode "600")]
}

def placed-unchanged []: nothing -> bool {
    if not ($CONF | path exists) { return false }
    let recorded = state-read base/wireguard system | get outputs | where target == $CONF | get --optional 0.hash
    $recorded != null and $recorded == (open --raw $CONF | hash sha256)
}
