use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

# its system verb pins the host keys from keys/ssh-host/<host>/
export const meta = {
    packages: {pacman: [knockd openbsd-netcat openssh]}
    secrets: ["ssh-host/{host}/ssh_host_ed25519_key" "ssh-host/{host}/ssh_host_mldsa44_ed25519_key" "ssh-host/{host}/ssh_host_ecdsa_key" "ssh-host/{host}/ssh_host_rsa_key"]
}
const SSH_HOST_KEYS = $meta.secrets | path basename

export const options = {
    port: {
        type: int
        default: 2222
        doc: "The port sshd listens on, reached through the port-knock (sshk, wake-pc, nftables, fail2ban)"
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
const PRIVATE_KEY = "configs/secrets/keys/ssh_privatekey.asc"
const PUBLIC_KEY = "configs/secrets/keys/ssh_publickey.asc"

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    step sshd ($cfg.port | into string)
}

def host-keys-pin []: nothing -> bool {
    let dir = host-file (system-secret ssh-host)
    let pinned = $SSH_HOST_KEYS | where {|k| ($dir | path join $k | path exists) }
    if ($pinned | is-empty) {
        # only with the secrets streamed unlocked: locked, a backup would land as plaintext over the git-crypt blobs
        if (system-secret ssh_publickey.asc | path exists) {
            let backup = host-file configs/secrets/keys/ssh-host
            print ("note: ssh: no pinned host keys, a reinstall changes this host's identity; back them up from the "
                + $"checkout: mkdir -p ($backup) && sudo cp ($HOST_KEY_DIR)/ssh_host_*_key ($backup)/ "
                + $"&& sudo chown $USER: ($backup)/*")
        }
        return false
    }
    $pinned | each {|k|
        let src = $dir | path join $k
        let dest = $HOST_KEY_DIR | path join $k
        if ($dest | path exists) and (open --raw $src) == (open --raw $dest) { return false }
        ^install -m600 $src $dest
        ^ssh-keygen -y -f $dest | ^install -m644 /dev/stdin $"($dest).pub"
        true
    } | any { $in }
}

export def sshd [port: string]: nothing -> nothing {
    let rekeyed = host-keys-pin
    # sshd -t needs host keys, absent before sshd's first start
    ^ssh-keygen -A
    let before = if ($DROPIN | path exists) { open --raw $DROPIN } else { null }
    open --raw 10-hardening.conf | str replace --all "@PORT@" $port | ^install -Dm644 /dev/stdin $DROPIN
    if (^sshd -t | complete).exit_code != 0 {
        if $before == null { rm $DROPIN } else { $before | save --force $DROPIN }
        error make {msg: "ssh: sshd rejects 10-hardening.conf, kept the previous config"}
    }
    ^systemctl enable sshd.service
    let active = (^systemctl is-active --quiet sshd.service | complete).exit_code == 0
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
        (file-render ssh-add.service (unit-dir | path join ssh-add.service) {DOTFILES: $env.DOTFILES})
        (if $owner { unit-enable ssh-add.service } else { unit-disable ssh-add.service })
        (file-text (ssh-dir config) $"Include ~/.ssh/config.d/*\n($hosts)" --mode 600)
        (if $owner and not (authorize-done) { step authorize })
        (file-render sshk.nu ($bin | path join sshk) {DOTFILES: $env.DOTFILES, PORT: $cfg.port, KNOCK: $knock}
            --mode 755)
        (if $homelab and $cfg.wake_router != null and $cfg.wake_host != null {
            let values = {
                ROUTER: $cfg.wake_router, ROUTER_TUNNEL: ($cfg.wake_router_tunnel | default "")
                HOST: $cfg.wake_host, PORT: $cfg.port, KNOCK: $knock
            }
            file-render wake-pc.nu ($bin | path join wake-pc) $values --mode 755
        })
    ]
}

def mode-is [file: path, mode: string]: nothing -> bool {
    ($file | path exists) and (ls --long --directory $file | get 0.mode) == $mode
}

# The authorized_keys text authorize writes over the current one: the secrets' keys in the managed block.
def authorized-keys-render []: nothing -> string {
    let pubkey = $env.DOTFILES | path join $PUBLIC_KEY
    let keys = [$pubkey ...(glob ../yubikey/ssh-*.pub) (ssh-dir id_ed25519.pub)]
        | where { secret-is-plaintext $in } | each { open --raw $in | str trim } | where $it != "" | uniq
    let file = ssh-dir authorized_keys
    let raw = if ($file | path exists) { open --raw $file } else { "" }
    let existing = $raw | lines
    # a locked secrets store cannot read the committed key, so only append what is readable and never prune
    if not (secret-is-plaintext $pubkey) {
        let missing = $keys | where $it not-in $existing
        return ($raw + ($missing | to text))
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
