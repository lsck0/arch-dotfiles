use module.nu *
use written.nu [written-record written-forget]
use converge.nu [recorded-hashes]

export const meta = {packages: {pacman: [openvpn wireguard-tools]}, volatile: true}

const CONF = "/etc/wireguard/wg0.conf"
const IFACE = "wg0"
const SECRET_NAME = '^[A-Za-z0-9._-]+$'

export def system [cfg: record] {
    let name = $env.WIREGUARD? | default ""
    if $name != "" and not ($name =~ $SECRET_NAME) {
        error make {msg: $"wireguard: '($name)' is not a secrets file name"}
    }
    step tunnel $name
}

# Writes or removes the wg config dot placed; a run without secrets never undoes one, a hand-made wg0.conf stays.
export def tunnel [name: string]: nothing -> nothing {
    let ours = ($CONF | path exists) and (open --raw $CONF | hash sha256) == (recorded-hashes | get --optional $CONF)
    if $name == "" {
        if $ours {
            ^wg-quick down $IFACE | complete | ignore
            rm $CONF
            written-forget $CONF
        }
        return
    }
    let secret = $env.DOTFILES_SECRETS? | default "/nonexistent" | path join $name
    if not ($secret | path exists) { return }
    let text = open --raw $secret
    # data only: wg-quick runs the *Up/*Down hooks as root, and SaveConfig would write back into it
    if not ($text =~ '(?m)^\[Interface\]') or ($text =~ '(?im)^\s*(PreUp|PostUp|PreDown|PostDown|SaveConfig)\s*=') {
        error make {msg: $"wireguard: ($name) is no [Interface] config or carries hooks/SaveConfig, keeping ($CONF)"}
    }
    if ($CONF | path exists) and not $ours and (open --raw $CONF) != $text {
        error make {msg: $"wireguard: ($CONF) was made by hand, move it away to let the dotfiles place ($name)"}
    }
    ^install -Dm600 $secret $CONF
    written-record $CONF
}
