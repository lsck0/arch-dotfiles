use module.nu *

export const meta = {volatile: true}

const CONF = "/etc/wireguard/protonvpn-netns.conf"
const LIB = "/usr/local/lib/protonvpn-netns"
const NS_ETC = "/etc/netns/protonvpn"
const UNIT = "protonvpn-netns.service"
# ahead of /usr/bin in every PATH; mpv-stream is mpv with its ytdl hook, which plain mpv leaves off
const SHIMS = [ani-cli yt-dlp mpv-stream]
# shimmed only when installed; qbittorrent binds proton0 itself
const VPN_FORCED = [gallery-dl spotdl nicotine]
const DNS_DEFAULT = "10.2.0.1"
const PRIVATE_KEY = '^\s*PrivateKey\s*=\s*[A-Za-z0-9+/]{43}=\s*$'
const HOOKS = '(?im)^\s*(PreUp|PostUp|PreDown|PostDown|SaveConfig)\s*='

def secret []: nothing -> path {
    $env.DOTFILES_SECRETS? | default "/nonexistent" | path join protonvpn-netns.conf
}

export def system [cfg: record] {
    # only the machine fact removes it: a run without secrets never undoes one that had them
    if $env.FORM_FACTOR? == "wsl" or not ((secret | path exists) or ($CONF | path exists)) { return [] }
    let restart = unit-restart $UNIT
    let shims = $SHIMS ++ ($VPN_FORCED | where { $"/usr/bin/($in)" | path exists })
    # validated first, a broken drop-in would lock every admin out
    if (^visudo -cf sudoers | complete).exit_code != 0 { error make {msg: "protonvpn-netns: sudoers does not parse"} }
    let nsswitch = open --raw /etc/nsswitch.conf
        | str replace --regex --multiline '^hosts:.*$' "hosts: files myhostname dns"
    [
        (step tunnel)
        (file-copy netns.nu $"($LIB)/netns" --mode 755 --then $restart)
        (file-copy run.nu $"($LIB)/run" --mode 755)
        ($shims | each { file-copy shim.nu $"/usr/local/bin/($in)" --mode 755 })
        # glibc in the namespace asks the tunnel's resolver directly, never resolved over its unix socket (a leak)
        (file-text $"($NS_ETC)/nsswitch.conf" $nsswitch)
        (file-copy sudoers /etc/sudoers.d/20-protonvpn-netns --mode 440)
        (unit-file $UNIT --enable --now --then $restart)
    ]
}

# data only: hooks would run as root, and a key masked on download (*****) never makes a tunnel
export def tunnel []: nothing -> nothing {
    if not (secret | path exists) { return }
    let text = open --raw (secret)
    if not ($text =~ '(?m)^\[Interface\]') or ($text =~ $HOOKS) or not ($text | lines | any { $in =~ $PRIVATE_KEY }) {
        let why = "is no wireguard config with a real PrivateKey (hooks are refused)"
        error make {msg: $"protonvpn-netns: secrets/protonvpn-netns.conf ($why)"}
    }
    let dns = $text | lines | parse --regex '^\s*DNS\s*=\s*(?<v>.*)$' | get --optional 0.v | default ""
        | split row "," | str trim | where { $in != "" and not ($in | str contains ":") } | get --optional 0
        | default $DNS_DEFAULT
    mkdir $NS_ETC
    let resolv = $"nameserver ($dns)\n"
    let changed = not ($CONF | path exists) or (open --raw $CONF) != $text
    let resolv_file = $"($NS_ETC)/resolv.conf"
    if not ($resolv_file | path exists) or (open --raw $resolv_file) != $resolv { $resolv | save --force $resolv_file }
    if $changed {
        ^install -Dm600 -o root -g root (secret) $CONF
        if (^systemctl cat $UNIT | complete).exit_code == 0 { ^systemctl restart $UNIT }
    }
}
