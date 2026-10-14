use module.nu *

export const meta = {packages: {native: [nftables]}}

const DIR = "/etc/nftables.d"
# (uid_t)-1 when tor is missing, which no process runs as
const NO_UID = "4294967295"
const UNITS = [fw-inbound.service fw-lockdown.service fw-egress.service]

# nft also arrives under wsl as docker's dependency, where windows owns the firewall
export def system [cfg: record] {
    if (which nft | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    # numeric, a name nft cannot resolve would fail the load
    let tor_uid = ^id -u tor | complete | if $in.exit_code == 0 { $in.stdout | str trim } else { $NO_UID }
    [
        (file-copy fw-inbound.nft $"($DIR)/fw-inbound.nft")
        (file-copy fw-lockdown.nft $"($DIR)/fw-lockdown.nft")
        (file-render fw-egress.nft $"($DIR)/fw-egress.nft" {TOR_UID: $tor_uid})
        ($UNITS | each { unit-file $in } | decls-flatten)
        # lockdown is the resting state until a home up or toggle-firewall.nu lifts it
        (unit-disable fw-inbound.service)
        (unit-enable fw-lockdown.service)
        # a vm guest leaves through its host, whose fw_egress forward chain already holds it
        (if $env.FORM_FACTOR? == "vm" { unit-disable fw-egress.service --now } else { unit-enable fw-egress.service })
        # never a start: it would drop a chosen state, and fw-egress off home would cut this run's network
        (exec "reload firewall" [systemctl try-reload-or-restart ...$UNITS])
    ]
}
