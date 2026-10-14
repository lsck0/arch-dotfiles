use module.nu *

export const meta = {packages: {native: [ethtool modemmanager networkmanager wpa_supplicant]}, volatile: true}

export const options = {
    untrusted_policy: {
        type: string
        default: firewall-only
        doc: ("Off the home network: lockdown-tor closes inbound and lets out only tor, dhcp and tunnels until a VPN "
            + "is up; firewall-only closes inbound and leaves egress open; off treats every network as home")
        label: "Untrusted networks"
        choices: [lockdown-tor firewall-only off]
        scope: machine
    }
    home_wired: {
        type: bool?
        default: null
        doc: ("Ethernet is always the home network: it keeps the hardware MAC and wake-on-lan (a desktop); "
            + "null detects it from the form factor")
        label: "Wired is home"
        scope: machine
    }
    home_gateways: {
        type: list<string>
        default: []
        doc: "Router MACs that make a network home, beside the admin's secrets/home-gateways"
        label: "Home gateways"
        scope: machine
    }
    homelab_dns: {
        type: string?
        default: null
        doc: "The homelab's split-horizon resolver, asked for homelab_domain out a home link (homelab machines)"
        scope: machine
    }
    homelab_domain: {
        type: string?
        default: null
        doc: "The homelab's DNS zone"
        scope: machine
    }
    homelab_subnets: {
        type: list<string>
        default: []
        doc: "The homelab's subnets, routed straight out a home link and through wg0 elsewhere"
        scope: machine
    }
}

const NM = "/etc/NetworkManager"
const DISPATCHERS = "/etc/NetworkManager/dispatcher.d"
const MAC = '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'
const IPV4 = '^(\d{1,3}\.){3}\d{1,3}$'
const CIDR4 = '^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$'
const DOMAIN = '^[A-Za-z0-9.-]+$'
const ONLINE_TIMEOUT_S = 60

export def detect [cfg: record]: nothing -> record {
    {home_wired: ($env.FORM_FACTOR? == "desktop")}
}

# a qmi/mbim modem makes a wwan*/wwp* iface and a cdc-wdm node; ModemManager idles needlessly without one
def has-modem []: nothing -> bool {
    (
        (glob /sys/class/net/{wwan,wwp}* | append (glob /dev/cdc-wdm*) | is-not-empty)
        or ((which mmcli | is-not-empty) and (^mmcli -L | complete | get stdout | str contains /Modem/))
        or (^nmcli -t -f TYPE device | complete | get stdout | lines | any { $in == gsm })
    )
}

# read by the dispatchers, tor-router and portmaster-bypass as root: only values of the shapes they expect
def homelab-env [cfg: record]: nothing -> any {
    if not (platform-has homelab) or $cfg.homelab_dns == null or $cfg.homelab_domain == null { return null }
    let bad = [[$cfg.homelab_dns $IPV4] [$cfg.homelab_domain $DOMAIN]] ++ ($cfg.homelab_subnets | each { [$in $CIDR4] })
        | where {|v| not ($v.0 =~ $v.1) }
    if ($bad | is-not-empty) { error make {msg: $"networkmanager: homelab value ($bad.0.0) is not of its shape"} }
    let nets = $cfg.homelab_subnets | str join ' '
    $"HOMELAB_DNS=($cfg.homelab_dns)\nHOMELAB_DOMAIN=($cfg.homelab_domain)\nHOMELAB_NETS=\"($nets)\"\n"
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let home_wired = $cfg.home_wired
    let bad = $cfg.home_gateways | where not ($it =~ $MAC)
    if ($bad | is-not-empty) { error make {msg: $"networkmanager: home_gateways has ($bad | str join ' '), not a mac"} }
    let homelab = homelab-env $cfg
    # a restart drops wifi for seconds, so only on a change, then the network is back for the modules after this one
    let online = $"nm-online -q --timeout=($ONLINE_TIMEOUT_S) || echo 'networkmanager: still offline' >&2"
    let restart = [sh -c $"systemctl restart NetworkManager.service && ($online)"]
    let dispatcher = {|src, name| file-copy $src $"($DISPATCHERS)/($name)" --mode 755 }
    [
        # ModemManager drives nmcli radio wwan (toggle-mobile)
        (if (which ModemManager | is-not-empty) and (has-modem) { unit-enable ModemManager.service --now } else { [] })
        (file-copy NetworkManager.conf $"($NM)/NetworkManager.conf" --then $restart)
        # NM's one auto wired profile serves every wired network: a laptop's ethernet stays random everywhere, so it is
        # never home (fail closed); a guest whose home is wired marks that one profile permanent by hand
        (if $home_wired { file-copy home-wired.conf $"($NM)/conf.d/10-home-wired.conf" --then $restart } else { [] })
        # run in name order, so home is decided before the others read it
        (do $dispatcher home-network.nu 70-home-network)
        # NM's connectivity check off at home, where the split-horizon dns cannot resolve its probe
        (do $dispatcher connectivity-check.nu 75-connectivity-check)
        (do $dispatcher homelab-routes.nu 80-homelab-routes)
        # the untrusted-network persona; the state machine is at its top
        (do $dispatcher persona-dispatcher.nu 90-anonymous-persona)
        (file-text $"($NM)/untrusted-policy" $"($cfg.untrusted_policy)\n")
        # a vm guest leaves through its host's kill switch
        (if $env.FORM_FACTOR? == "vm" { file-text $"($NM)/vm-guest" "" } else { [] })
        (if $homelab != null { file-text $"($NM)/homelab.env" $homelab } else { [] })
        (step home ($home_wired | into string) ...$cfg.home_gateways)
    ]
}

# the admin's secrets (data in DOTFILES_SECRETS): saved home wifis keep the hardware mac and ipv6, every other network
# gets a random mac and no ipv6 (persona dispatcher); home-gateways replaces the list, a run without it keeps it
export def home [home_wired: string, ...gateways: string]: nothing -> nothing {
    let secrets = $env.DOTFILES_SECRETS? | default "/nonexistent"
    let profiles = ^nmcli -g UUID,TYPE connection show | lines | parse "{uuid}:{type}"
    let wifi = $secrets | path join wifi
    if ($wifi | path exists) {
        let ssids = open --raw $wifi | lines | each { split row "\t" | first } | where $it != ""
        # the ssid is only ever compared, never an nmcli argument
        for p in ($profiles | where type == 802-11-wireless) {
            if (^nmcli -g 802-11-wireless.ssid connection show $p.uuid | str trim) in $ssids {
                ^nmcli connection modify $p.uuid 802-11-wireless.cloned-mac-address permanent ipv6.method auto
            }
        }
    }
    if $home_wired == "true" {
        for p in ($profiles | where type == 802-3-ethernet) { ^nmcli connection modify $p.uuid ipv6.method auto }
    }
    let file = $"($NM)/home-gateways"
    let secret = $secrets | path join home-gateways
    let listed = if ($secret | path exists) {
        let lines = open --raw $secret | lines
        # comments and blanks never equal a mac in home-network.nu's whole-line match, so they may stay
        if ($lines | any {|l| not ($l =~ $MAC or $l =~ '^(#.*)?$') }) or not ($lines | any { $in =~ $MAC }) {
            error make {msg: $"networkmanager: home-gateways is not one mac address per line, keeping ($file)"}
        }
        $lines
    } else if ($file | path exists) { open --raw $file | lines } else { [] }
    let want = $listed | append ($gateways | where $it not-in $listed)
    if ($want | is-not-empty) { $want | str join "\n" | $"($in)\n" | save --force $file }
}
