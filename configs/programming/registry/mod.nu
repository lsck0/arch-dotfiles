use module.nu *

export const meta = {packages: {pacman: [podman]}}

const SECRET = "configs/secrets/keys/registry.env"

# podman's login for the homelab registry; podman reads ~/.config/containers/auth.json after the runtime dir's
export def link [cfg: record] {
    if not (profile-has secrets) { return [] }
    let secret = $env.DOTFILES | path join $SECRET
    let target = xdg config containers auth.json
    let text = if (secret-is-plaintext $secret) {
        let r = open --raw $secret | lines | parse --regex '^(?<k>[A-Z_]+)=(?<v>.*)$'
            | reduce --fold {} {|e, acc| $acc | insert $e.k ($e.v | str trim) }
        let auth = $"($r.REGISTRY_USER):($r.REGISTRY_PASSWORD)" | encode base64
        {auths: {$r.REGISTRY_URL: {auth: $auth}}} | to json
    } else if ($target | path exists) { open --raw $target } else { null }
    if $text == null { return [] }
    file-text $target $"($text)\n" --mode 600
}
