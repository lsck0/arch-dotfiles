use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# its system verb pins the host keys from keys/ssh-host/<host>/
export const meta = {
    packages: {pacman: [knockd openbsd-netcat openssh]}
    secrets: ["ssh-host/{host}/ssh_host_ed25519_key" "ssh-host/{host}/ssh_host_mldsa44_ed25519_key" "ssh-host/{host}/ssh_host_ecdsa_key" "ssh-host/{host}/ssh_host_rsa_key"]
    native_only: [system]
    # wake-pc renders the initramfs unlock port from there
    inputs: [configs/base/boot/remote-unlock/services/tinysshd.conf]
}
const SSH_HOST_KEYS = $meta.secrets | path basename

export const options = {
    server: {
        type: bool
        default: true
        doc: ("Run sshd behind the port-knock, and base/endlessh's tarpit on 22; off keeps the client and ssh-agent "
            + "(wake-pc and offload need it on the target)")
        label: "SSH server"
    }
    port: {
        type: int
        default: 2222
        doc: "The port sshd listens on, reached through the port-knock (sshk, wake-pc, nftables)"
        label: "sshd port"
        min: 1
        max: 65535
    }
    knock: {
        type: list<int>
        default: [9003 7001 8002]
        doc: "The three ports knocked in order to open the sshd port to that address (sshk, wake-pc, nftables)"
        label: "Knock sequence"
    }
    homelab_hosts: {
        type: list<string>
        default: $HOMELAB.ssh_hosts
        doc: ("ssh patterns of the homelab's guests, router and hypervisor: root, accept-new host keys from "
            + "known_hosts.homelab (homelab profiles only); default the lab's zones, router and hypervisor")
        label: "Homelab ssh hosts"
    }
    wake_router: {
        type: string?
        default: $HOMELAB.router
        doc: "The always-on homelab router whose `wol-pc` wakes the desktop (wake-pc, homelab profiles only)"
    }
    wake_router_tunnel: {
        type: string?
        default: null
        doc: ("The router's address inside the wireguard tunnel, which wake-pc asks away from home: its lan address is "
            + "unrouted there, or shadowed by a foreign lan on the same subnet")
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
const HOST_KEY_DIR = "/etc/ssh"
const PRIVATE_KEY = "configs/secrets/keys/ssh/private.asc"
const PUBLIC_KEY = "configs/secrets/keys/ssh/public.asc"

export def system [cfg: record] {
    if not $cfg.server { return (unit-disable sshd.service --now) }
    step sshd ($cfg.port | into string)
}

def host-keys-pin []: nothing -> bool {
    # only with the secrets streamed unlocked: locked, a backup would land as plaintext over the git-crypt blobs
    let backup = if (system-secret ssh/public.asc | path exists) { host-file configs/secrets/keys/ssh-host }
    let pin = host-keys-install (host-file (system-secret ssh-host)) $HOST_KEY_DIR $backup
    if $pin.note != null { print $pin.note }
    $pin.rekeyed
}

# Copies the pinned host keys in dir over dest's where they differ (mode 600, the public half 644 beside): rekeyed when
# one changed. Without any pinned key the note names the backup command, when there is a backup dir to name.
export def host-keys-install [dir: path, dest_dir: path, backup: any]: nothing -> record<rekeyed: bool, note: any> {
    let pinned = $SSH_HOST_KEYS | where {|k| ($dir | path join $k | path exists) }
    if ($pinned | is-empty) {
        let note = if $backup != null {
            ("note: ssh: no pinned host keys, a reinstall changes this host's identity; back them up from the "
                + $"checkout: mkdir -p ($backup) && sudo cp ($dest_dir)/ssh_host_*_key ($backup)/ "
                + $"&& sudo chown $USER: ($backup)/*")
        }
        return {rekeyed: false, note: $note}
    }
    let rekeyed = $pinned | each {|k|
        let src = $dir | path join $k
        let dest = $dest_dir | path join $k
        if ($dest | path exists) and (open --raw $src) == (open --raw $dest) { return false }
        ^install -m600 $src $dest
        ^ssh-keygen -y -f $dest | ^install -m644 /dev/stdin $"($dest).pub"
        true
    } | collect | any { $in }
    {rekeyed: $rekeyed, note: null}
}

export def sshd [port: string]: nothing -> nothing {
    let rekeyed = host-keys-pin
    # sshd -t needs host keys, absent before sshd's first start
    ^ssh-keygen -A
    let before = if ($DROPIN | path exists) { open --raw $DROPIN } else { null }
    open --raw config/10-hardening.conf | str replace --all "@PORT@" $port | ^install -Dm644 /dev/stdin $DROPIN
    if (^sshd -t | complete).exit_code != 0 {
        if $before == null { rm $DROPIN } else { $before | save --force $DROPIN }
        error make {msg: "ssh: sshd rejects 10-hardening.conf, kept the previous config"}
    }
    ^systemctl enable sshd.service
    let active = unit-active sshd.service
    # base/endlessh's tarpit holds 22 until its own verb runs after this one
    if $port == "22" { do { ^systemctl disable --now endlessh.service } | complete | ignore }
    if not $active or $rekeyed or (open --raw $DROPIN) != $before { ^systemctl reload-or-restart sshd.service }
}

def ssh-dir [...file: string]: nothing -> path {
    $nu.home-dir | path join .ssh ...$file
}

export def link [cfg: record] {
    let owner = profile-has secrets
    let homelab = $owner and (platform-has homelab)
    let bin = $nu.home-dir | path join .local bin
    let knock = $cfg.knock | str join " "
    let hosts = if $homelab and ($cfg.homelab_hosts | is-not-empty) {
        [
            $"Host ($cfg.homelab_hosts | str join ' ')" "    User root"
            "    UserKnownHostsFile ~/.ssh/known_hosts.homelab" "    StrictHostKeyChecking accept-new" ""
        ] | str join "\n"
    } else { "" }
    [
        # claimed disabled: an orphan disable of the vendor unit would take ssh-agent.socket along (Also=)
        (unit-disable ssh-agent.service --now)
        (unit-enable ssh-agent.socket --now)
        (unit-file services/ssh-add.service --values {DOTFILES: $env.DOTFILES})
        (unit-switch ssh-add.service $owner)
        (file-text (ssh-dir config) $"Include ~/.ssh/config.d/*\n($hosts)" --mode 600)
        (if $owner and not (authorize-done) { step authorize })
        (file-render scripts/sshk.nu ($bin | path join sshk) {DOTFILES: $env.DOTFILES, PORT: $cfg.port, KNOCK: $knock}
            --mode 755)
        (if $homelab and $cfg.wake_router != null and $cfg.wake_host != null {
            # the initramfs tinysshd's port, read where it is set (offload reads it the same way)
            let unlock = open --raw ../boot/remote-unlock/services/tinysshd.conf | parse --regex '(?m)^Environment=SSHD_PORT=(?<p>\d+)'
            let values = {
                DOTFILES: $env.DOTFILES, ROUTER: $cfg.wake_router, ROUTER_TUNNEL: ($cfg.wake_router_tunnel | default "")
                HOST: $cfg.wake_host, PORT: $cfg.port, KNOCK: $knock
                UNLOCK_PORT: $unlock.0.p
            }
            file-render scripts/wake-pc.nu ($bin | path join wake-pc) $values --mode 755
        })
    ]
}

def mode-is [file: path, mode: string]: nothing -> bool {
    ($file | path exists) and (ls --long --directory $file | get 0.mode) == $mode
}

# The authorized_keys text authorize writes over the current one: the secrets' keys in the managed block.
def authorized-keys-render []: nothing -> string {
    let pubkey = $env.DOTFILES | path join $PUBLIC_KEY
    let keys = [$pubkey ...(glob ../yubikey/config/ssh-*.pub) (ssh-dir id_ed25519.pub)]
        | where { secret-is-plaintext $in } | each { open --raw $in | str trim } | where $it != "" | uniq
    let file = ssh-dir authorized_keys
    let raw = if ($file | path exists) { open --raw $file } else { "" }
    let existing = $raw | lines
    # a locked secrets store cannot read the committed key, so only append what is readable and never prune
    if not (secret-is-plaintext $pubkey) {
        let missing = $keys | where $it not-in $existing
        let base = if $raw == "" or ($raw | str ends-with "\n") { $raw } else { $raw + "\n" }
        return ($base + ($missing | to text))
    }
    # rebuild the managed block so a key rotated out of the sources loses access; lines outside it are kept
    let begin = $existing | enumerate | where item == $MANAGED_BEGIN | get --optional 0.index
    let end = $existing | enumerate | where item == $MANAGED_END | get --optional 0.index
    let kept = if $begin != null and $end != null and $end > $begin {
        ($existing | first $begin) ++ ($existing | skip ($end + 1))
    } else { $existing }
    let kept = $kept | where $it not-in $keys
    ($kept ++ [$MANAGED_BEGIN] ++ $keys ++ [$MANAGED_END]) | to text
}

def authorize-done []: nothing -> bool {
    let key = $env.DOTFILES | path join $PRIVATE_KEY
    let file = ssh-dir authorized_keys
    let modes = (not (secret-is-plaintext $key) or (mode-is $key rw-------)) and (mode-is (ssh-dir) rwx------)
    $modes and (mode-is $file rw-------) and (open --raw $file) == (authorized-keys-render)
}

# Installs the secrets' authorized_keys; git-crypt checks it out 0644, which ssh refuses.
export def authorize []: nothing -> nothing {
    let key = $env.DOTFILES | path join $PRIVATE_KEY
    if (secret-is-plaintext $key) { ^chmod 600 $key }
    mkdir (ssh-dir)
    ^chmod 700 (ssh-dir)
    let file = ssh-dir authorized_keys
    let out = authorized-keys-render
    if not ($file | path exists) { touch $file }
    ^chmod 600 $file
    if $out != (open --raw $file) { $out | save --force $file }
}
