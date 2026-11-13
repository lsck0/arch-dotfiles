use module.nu *

# reads, not deps: the firewall never waits on another module's packages, a fresh install gets it from the first run
export const meta = {packages: {native: [nftables]}, volatile: true, reads: [base/networkmanager base/ssh]}

export const options = {
    ssh_knock_window: {
        type: string
        default: "1h"
        doc: "How long a successful SSH port-knock keeps that IP allowed through to base/ssh.port, nft timeout syntax"
        label: "SSH knock access window"
    }
}

const DIR = "/etc/nftables.d"
const HOOK = "/etc/pacman.d/hooks/fw-egress-uids.hook"
const UNITS = [fw-inbound.service fw-lockdown.service fw-egress.service]
const NFT_DURATION = '^(\d+(ms|[dhms]))+$'
const KNOCK_LENGTH = 3
const PORT_MAX = 65535
const LOCKDOWN_START = "systemctl try-reload-or-restart fw-lockdown.service
systemctl is-active -q fw-inbound.service fw-lockdown.service || systemctl start fw-lockdown.service"

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
    # without networkmanager no link is ever trusted: fail closed
    let policy = $cfg.deps?."base/networkmanager"?.untrusted_policy? | default lockdown-tor
    let inbound = {
        SSH_KNOCK_WINDOW: $cfg.ssh_knock_window, SSH_PORT: $ssh.port
        KNOCK_1: $knock.0, KNOCK_2: $knock.1, KNOCK_3: $knock.2
    }
    # only on a changed ruleset, it empties the knock and portal sets; never a start, fw-egress off a trusted network cuts this run
    [
        # units first, so a fresh install's ruleset reload finds them
        ($UNITS | each {|u| unit-file $u --then (unit-restart $u --reload --if-running) })
        (file-render fw-inbound.nft $"($DIR)/fw-inbound.nft" $inbound
            --then (unit-restart fw-inbound.service --reload --if-running))
        # the inbound lockdown holds from the first run, unless a trusted link already loaded fw-inbound
        (file-copy fw-lockdown.nft $"($DIR)/fw-lockdown.nft" --then [sh -c $LOCKDOWN_START])
        # the escape uids are filled in by the unit at start, so it never waits on tor being installed
        (file-copy fw-egress.nft $"($DIR)/fw-egress.nft"
            --then (unit-restart fw-egress.service --reload --if-running))
        (file-copy fw-egress-uids.hook $HOOK)
        (unit-disable fw-inbound.service)
        (unit-enable fw-lockdown.service)
        # fail closed: without tor, pacman's escape in fw-egress.nft is how tor gets installed
        (if $env.FORM_FACTOR? != "vm" and $policy == lockdown-tor {
            unit-enable fw-egress.service
        } else {
            unit-disable fw-egress.service --now
        })
    ]
}
