use module.nu *

export const meta = {packages: {native: [nftables]}, volatile: true, deps: [tor]}

export const options = {
    ssh_knock_window: {
        type: string
        default: "1h"
        doc: "How long a successful SSH port-knock keeps that IP allowed through to port 2222, nft timeout syntax"
        label: "SSH knock access window"
        scope: machine
    }
}

const DIR = "/etc/nftables.d"
# (uid_t)-1 when tor is missing, which no process runs as
const NO_UID = "4294967295"
const UNITS = [fw-inbound.service fw-lockdown.service fw-egress.service]

export def system [cfg: record] {
    # nft also arrives under wsl as docker's dependency, where windows owns the firewall
    if (which nft | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    let tor_uid = ^id -u tor | complete | if $in.exit_code == 0 { $in.stdout | str trim } else { $NO_UID }
    [
        (file-render fw-inbound.nft $"($DIR)/fw-inbound.nft" {SSH_KNOCK_WINDOW: $cfg.ssh_knock_window})
        (file-copy fw-lockdown.nft $"($DIR)/fw-lockdown.nft")
        (file-render fw-egress.nft $"($DIR)/fw-egress.nft" {TOR_UID: $tor_uid})
        ($UNITS | each { unit-file $in } | decls-flatten)
        (unit-disable fw-inbound.service)
        (unit-enable fw-lockdown.service)
        (if $env.FORM_FACTOR? == "vm" { unit-disable fw-egress.service --now } else { unit-enable fw-egress.service })
        # never a start: it would drop a chosen state, and fw-egress off home would cut this run's network
        (exec "reload firewall" [systemctl try-reload-or-restart ...$UNITS])
    ]
}
