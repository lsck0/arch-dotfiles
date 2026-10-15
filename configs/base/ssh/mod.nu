use module.nu *

export const meta = {packages: {pacman: [knockd openbsd-netcat openssh]}}

export const options = {
    homelab_hosts: {
        type: list<string>
        default: []
        doc: ("ssh patterns of the homelab's guests, router and hypervisor: root, accept-new host keys from "
            + "known_hosts.homelab (homelab profiles only)")
        label: "Homelab ssh hosts"
        scope: machine
    }
    wake_router: {
        type: string?
        default: null
        doc: "The always-on homelab router whose `wol-pc` wakes the desktop (wake-pc, homelab profiles only)"
        scope: machine
    }
    wake_host: {
        type: string?
        default: null
        doc: "The desktop wake-pc wakes and then ssh-es into"
        scope: machine
    }
}

const DROPIN = "/etc/ssh/sshd_config.d/10-hardening.conf"

# real sshd on knocked 2222, keys and wheel only, never root; windows owns inbound under wsl, where the knock
# chain, fail2ban and endlessh all declare nothing
export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    step sshd
}

# a drop-in sshd rejects is rolled back, the running sshd left alone
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
    let homelab = profile-has homelab
    let identity = profile-has identity
    let hosts = if $homelab and ($cfg.homelab_hosts | is-not-empty) {
        [
            $"Host ($cfg.homelab_hosts | str join ' ')" "    User root"
            "    UserKnownHostsFile ~/.ssh/known_hosts.homelab" "    StrictHostKeyChecking accept-new"
        ] | each { $"($in)\n" } | str join
    }
    [
        (unit-file ssh-agent.service --enable)
        (unit-file ssh-add.service)
        (if $identity { unit-enable ssh-add.service } else { unit-disable ssh-add.service })
        (if $hosts != null { file-text (ssh-dir | path join config) $hosts --mode 600 } else { [] })
        (if $identity { step authorize } else { [] })
        (link-commands sshk.nu)
        (if $homelab and $cfg.wake_router != null and $cfg.wake_host != null {
            let values = {ROUTER: $cfg.wake_router, HOST: $cfg.wake_host}
            file-render wake-pc.nu ($nu.home-dir | path join .local bin wake-pc) $values --mode 755
        } else { [] })
    ]
}

# git-crypt checks the secrets key out 0644, which ssh refuses
export def authorize []: nothing -> nothing {
    let secrets = $env.DOTFILES | path join secrets
    let key = $secrets | path join ssh_privatekey.asc
    if (secret-is-plaintext $key) { ^chmod 600 $key }
    mkdir (ssh-dir)
    ^chmod 700 (ssh-dir)
    let file = ssh-dir | path join authorized_keys
    if not ($file | path exists) { touch $file }
    ^chmod 600 $file
    let have = open --raw $file | lines
    let sources = [($secrets | path join ssh_publickey.asc) ...(glob ../yubikey/ssh-*.pub)]
    let keys = $sources | append (ssh-dir | path join id_ed25519.pub)
        | where { secret-is-plaintext $in } | each { open --raw $in | str trim } | where $it not-in $have | uniq
    if ($keys | is-not-empty) { $"($keys | str join "\n")\n" | save --append $file }
}
