use module.nu *

export const meta = {packages: {native: [nftables]}, volatile: true, deps: [base/tor base/networkmanager base/ssh]}

export const options = {
    ssh_knock_window: {
        type: string
        default: "1h"
        doc: "How long a successful SSH port-knock keeps that IP allowed through to base/ssh.port, nft timeout syntax"
        label: "SSH knock access window"
    }
}

const DIR = "/etc/nftables.d"
# (uid_t)-1 when tor is missing, which no process runs as
const NO_UID = "4294967295"
const UNITS = [fw-inbound.service fw-lockdown.service fw-egress.service]
const NFT_DURATION = '^(\d+(ms|[dhms]))+$'
const KNOCK_LENGTH = 3
const PORT_MAX = 65535

export def system [cfg: record] {
    # nft also arrives under wsl as docker's dependency, where windows owns the firewall
    if (which nft | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    if not ($cfg.ssh_knock_window =~ $NFT_DURATION) {
        error make {msg: $"nftables: ssh_knock_window ($cfg.ssh_knock_window) is not an nft duration"}
    }
    let ssh = $cfg.deps."base/ssh"
    let knock = $ssh.knock
    let distinct = ($knock | uniq | length) == $KNOCK_LENGTH and ($knock | length) == $KNOCK_LENGTH
    if not $distinct or $ssh.port in $knock or ($knock | any { $in < 1 or $in > $PORT_MAX }) {
        error make {
            msg: $"nftables: base/ssh knock ($knock | to nuon) is not ($KNOCK_LENGTH) distinct ports other than sshd's"
        }
    }
    let tor_uid = ^id -u tor | complete | if $in.exit_code == 0 { $in.stdout | str trim } else { $NO_UID }
    # without networkmanager nothing stops it off home, as under lockdown-tor
    let policy = $cfg.deps?."base/networkmanager"?.untrusted_policy? | default lockdown-tor
    # only on a changed ruleset, it empties the knock and portal sets; never a start, fw-egress off home cuts this run
    let reload = {|unit| [systemctl try-reload-or-restart $unit] }
    let inbound = {
        SSH_KNOCK_WINDOW: $cfg.ssh_knock_window, SSH_PORT: $ssh.port
        KNOCK_1: $knock.0, KNOCK_2: $knock.1, KNOCK_3: $knock.2
    }
    [
        # units first, so a fresh install's ruleset reload finds them
        ($UNITS | each {|u| unit-file $u --then (do $reload $u) } | decls-flatten)
        (file-render fw-inbound.nft $"($DIR)/fw-inbound.nft" $inbound --then (do $reload fw-inbound.service))
        (file-copy fw-lockdown.nft $"($DIR)/fw-lockdown.nft" --then (do $reload fw-lockdown.service))
        (file-render fw-egress.nft $"($DIR)/fw-egress.nft" {TOR_UID: $tor_uid} --then (do $reload fw-egress.service))
        (unit-disable fw-inbound.service)
        (unit-enable fw-lockdown.service)
        (if $env.FORM_FACTOR? != "vm" and $policy == lockdown-tor {
            unit-enable fw-egress.service
        } else {
            unit-disable fw-egress.service --now
        })
    ]
}
