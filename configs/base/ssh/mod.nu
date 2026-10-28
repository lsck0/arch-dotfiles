use module.nu *

export const meta = {packages: {pacman: [knockd openbsd-netcat openssh]}}

export const options = {
    homelab_hosts: {
        type: list<string>
        default: []
        doc: ("ssh patterns of the homelab's guests, router and hypervisor: root, accept-new host keys from "
            + "known_hosts.homelab (homelab profiles only)")
        label: "Homelab ssh hosts"
    }
    wake_router: {
        type: string?
        default: null
        doc: "The always-on homelab router whose `wol-pc` wakes the desktop (wake-pc, homelab profiles only)"
    }
    wake_host: {
        type: string?
        default: null
        doc: "The desktop wake-pc wakes and then ssh-es into"
    }
}

const DROPIN = "/etc/ssh/sshd_config.d/10-hardening.conf"
const MANAGED_BEGIN = "# arch-dotfiles managed keys (rebuilt from sources; edits outside this block are kept)"
const MANAGED_END = "# end arch-dotfiles managed keys"

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    step sshd
}

export def sshd []: nothing -> nothing {
    # sshd -t needs host keys, absent before sshd's first start
    ^ssh-keygen -A
    let before = if ($DROPIN | path exists) { open --raw $DROPIN } else { null }
    ^install -Dm644 10-hardening.conf $DROPIN
    if (^sshd -t | complete).exit_code != 0 {
        if $before == null { rm $DROPIN } else { $before | save --force $DROPIN }
        error make {msg: "ssh: sshd rejects 10-hardening.conf, kept the previous config"}
    }
    ^systemctl enable sshd.service
    ^systemctl reload-or-restart sshd.service
}

def ssh-dir []: nothing -> path {
    $nu.home-dir | path join .ssh
}

export def link [cfg: record] {
    let owner = profile-has secrets
    let homelab = $owner and (platform-has homelab)
    let hosts = if $homelab and ($cfg.homelab_hosts | is-not-empty) {
        [
            $"Host ($cfg.homelab_hosts | str join ' ')" "    User root"
            "    UserKnownHostsFile ~/.ssh/known_hosts.homelab" "    StrictHostKeyChecking accept-new"
        ] | each { $"($in)\n" } | str join
    }
    [
        (unit-file ssh-agent.service --enable)
        (file-render ssh-add.service (unit-dir | path join ssh-add.service) {DOTFILES: $env.DOTFILES})
        (if $owner { unit-enable ssh-add.service } else { unit-disable ssh-add.service })
        (file-text (ssh-dir | path join config) $"Include ~/.ssh/config.d/*\n($hosts | default '')" --mode 600)
        (if $owner { step authorize } else { [] })
        (link-commands sshk.nu)
        (if $homelab and $cfg.wake_router != null and $cfg.wake_host != null {
            let values = {ROUTER: $cfg.wake_router, HOST: $cfg.wake_host}
            file-render wake-pc.nu ($nu.home-dir | path join .local bin wake-pc) $values --mode 755
        } else { [] })
    ]
}

# Installs the secrets' authorized_keys; git-crypt checks it out 0644, which ssh refuses.
export def authorize []: nothing -> nothing {
    let secrets = $env.DOTFILES | path join configs secrets keys
    let key = $secrets | path join ssh_privatekey.asc
    if (secret-is-plaintext $key) { ^chmod 600 $key }
    mkdir (ssh-dir)
    ^chmod 700 (ssh-dir)
    let file = ssh-dir | path join authorized_keys
    if not ($file | path exists) { touch $file }
    ^chmod 600 $file
    let pubkey = $secrets | path join ssh_publickey.asc
    let sources = [$pubkey ...(glob ../yubikey/ssh-*.pub)]
    let keys = $sources | append (ssh-dir | path join id_ed25519.pub)
        | where { secret-is-plaintext $in } | each { open --raw $in | str trim } | where $it != "" | uniq
    let existing = open --raw $file | lines
    # a locked secrets store cannot read the committed key, so only append what is readable and never prune
    if not (secret-is-plaintext $pubkey) {
        let missing = $keys | where $it not-in $existing
        if ($missing | is-not-empty) { $"($missing | str join "\n")\n" | save --append $file }
        return
    }
    # rebuild the managed block so a key rotated out of the sources loses access; lines outside it are kept
    let begin = $existing | enumerate | where item == $MANAGED_BEGIN | get --optional 0.index
    let end = $existing | enumerate | where item == $MANAGED_END | get --optional 0.index
    let kept = if $begin != null and $end != null and $end > $begin {
        ($existing | first $begin) ++ ($existing | skip ($end + 1))
    } else { $existing }
    let kept = $kept | where $it not-in $keys
    let out = ($kept ++ [$MANAGED_BEGIN] ++ $keys ++ [$MANAGED_END]) | str join "\n" | $"($in)\n"
    if $out != (open --raw $file) { $out | save --force $file }
}
