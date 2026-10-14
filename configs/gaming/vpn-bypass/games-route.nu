#!/usr/bin/nu --no-config-file
# NM dispatcher: keep routing table 100 pointed at the real physical gateway and a fwmark rule that sends the games
# group's marked packets (games-bypass.nft) into it. with proton0 up the main table's default is the tunnel; table 100
# stays on the physical link, so a marked game packet egresses on the real link instead. fail safe: no gateway, no
# table and no rule, and an unmarked or unrouted packet just follows the main table back onto the vpn

# the skb mark games-bypass.nft sets and fw-egress' game_mark lets out; kept in sync with both
const GAME_MARK = "0x6761"
const TABLE = "100"
# above homelab (30000) and a full-tunnel vpn's own rules, below the kernel's local (0)
const PRIORITY = "9000"
const FAMILIES = ["-4" "-6"]

def --wrapped out [...argv: string]: nothing -> string {
    do { run-external ...$argv } | complete | get stdout
}

def --wrapped attempt [...argv: string]: nothing -> nothing {
    let r = do { run-external ...$argv } | complete
    if $r.exit_code != 0 { print --stderr --no-newline $r.stderr }
}

# nmcli reports the link's own gateway even when proton0 owns the main default; ip route is the fallback at first up.
# nmcli -g escapes the colons of an ipv6 gateway (fe80\:\:...)
def gateway [iface: string, family: string]: nothing -> string {
    let field = if $family == "-4" { "IP4.GATEWAY" } else { "IP6.GATEWAY" }
    let listed = out nmcli -g $field device show $iface | lines | get --optional 0 | default "" | str replace --all '\' ''
    if $listed != "" or $family == "-6" { return $listed }
    out ip -4 route show default dev $iface | lines | get --optional 0 | default "" | split row " " | get --optional 2
    | default ""
}

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up dhcp4-change down] { return }
    # physical wifi/ethernet only; never a tunnel or virtual device
    if not ($"/sys/class/net/($iface)/device" | path exists) { return }

    if $action == down {
        for family in $FAMILIES { out ip $family route flush table $TABLE dev $iface | ignore }
        # another physical link may still own the table; only drop the rules once it is empty
        if ($FAMILIES | all {|f| out ip $f route show table $TABLE | is-empty }) {
            for family in $FAMILIES { out ip $family rule del fwmark $GAME_MARK lookup $TABLE priority $PRIORITY | ignore }
        }
        return
    }

    for family in $FAMILIES {
        let via = gateway $iface $family
        if $via == "" { continue }
        attempt ip $family route replace default via $via dev $iface table $TABLE
        if not (out ip $family rule list priority $PRIORITY | str contains $"fwmark ($GAME_MARK)") {
            attempt ip $family rule add fwmark $GAME_MARK lookup $TABLE priority $PRIORITY
        }
    }
}
