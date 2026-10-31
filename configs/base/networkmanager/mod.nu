use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

export const meta = {packages: {native: [modemmanager networkmanager wpa_supplicant]}, volatile: true}

export const options = {
    untrusted_policy: {
        type: string
        default: firewall-only
        doc: ("Off the home network: lockdown-tor closes inbound and lets out only tor, dhcp and tunnels until a VPN "
            + "is up; firewall-only closes inbound and leaves egress open; off treats every network as home")
        label: "Untrusted networks"
        choices: [lockdown-tor firewall-only off]
    }
    home_wired: {
        type: bool?
        default: null
        doc: "Ethernet is always the home network and keeps its hardware MAC (a desktop); null detects it from the form factor"
        label: "Wired is home"
    }
    wake_on_lan: {
        type: bool
        default: false
        doc: "Wake on a magic packet over ethernet (udev sets it on every wired link, NetworkManager leaves it)"
        label: "Wake-on-LAN"
    }
    wifi_radio: {
        type: bool?
        default: null
        doc: ("Wi-Fi radio on at first boot; off on a desktop wired to the network, so only the link in use is up. "
            + "Later toggles (toggle-wifi) persist in NetworkManager's own state; null detects it")
        label: "Wi-Fi radio"
    }
    home_gateways: {
        type: list<string>
        default: []
        doc: "Router MACs that make a network home, beside the admin's configs/secrets/keys/home-gateways"
    }
    homelab_dns: {
        type: string?
        default: $HOMELAB.router
        doc: "The homelab's split-horizon resolver, asked for homelab_domain out a home link (homelab machines); default the lab's router"
    }
    homelab_domain: {
        type: string?
        default: $HOMELAB.domain
        doc: "The homelab's DNS zone"
    }
    homelab_subnets: {
        type: list<string>
        default: $HOMELAB.subnets
        doc: "The homelab's subnets, routed straight out a home link and through wg0 elsewhere; default the lab's zones"
    }
}

const NM = "/etc/NetworkManager"
const DISPATCHERS = "/etc/NetworkManager/dispatcher.d"
const HOME_NETWORK = "/run/home-network"
const LOCKDOWN_MARKER = "/run/persona-lockdown"
const MAC = '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'
const IPV4 = '^(\d{1,3}\.){3}\d{1,3}$'
const CIDR4 = '^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$'
const DOMAIN = '^[A-Za-z0-9.-]+$'
const ONLINE_TIMEOUT_S = 60
# behind wg0's routes and table 178's copies, so the lab fails fast off home
const HOMELAB_UNREACHABLE_METRIC = 4000
const ARPHRD_ETHER = "1"
const WIFI_OFF_MARK = "/var/lib/NetworkManager/dotfiles-wifi-off"

def ethernet-up []: nothing -> bool {
    ls /sys/class/net | get name | where {|n| ($n | path join device | path exists) and not ($n | path join wireless | path exists) }
        | where {|n| (try { open --raw ($n | path join type) | str trim } catch { "" }) == $ARPHRD_ETHER }
        | any {|n| (try { open --raw ($n | path join carrier) | str trim } catch { "0" }) == "1" }
}

export def detect [cfg: record]: nothing -> record {
    let desktop = $env.FORM_FACTOR? == "desktop"
    {home_wired: $desktop, wifi_radio: (not ($desktop and (ethernet-up)))}
}

def has-modem []: nothing -> bool {
    (
        (glob /sys/class/net/{wwan,wwp}* | append (glob /dev/cdc-wdm*) | is-not-empty)
        or ((which mmcli | is-not-empty) and (^mmcli -L | complete | get stdout | str contains /Modem/))
        or (^nmcli -t -f TYPE device | complete | get stdout | lines | any { $in == gsm })
    )
}

# Read as root by the dispatchers, tor-router and portmaster-bypass: only values of the shapes they expect.
def homelab-env [cfg: record]: nothing -> any {
    if not (platform-has homelab) or $cfg.homelab_dns == null or $cfg.homelab_domain == null { return null }
    let bad = [[$cfg.homelab_dns $IPV4] [$cfg.homelab_domain $DOMAIN]] ++ ($cfg.homelab_subnets | each { [$in $CIDR4] })
        | where {|v| not ($v.0 =~ $v.1) }
    if ($bad | is-not-empty) { error make {msg: $"networkmanager: homelab value ($bad.0.0) is not of its shape"} }
    let nets = $cfg.homelab_subnets | str join ' '
    let lab = $"HOMELAB_DNS=($cfg.homelab_dns)\nHOMELAB_DOMAIN=($cfg.homelab_domain)\nHOMELAB_NETS=\"($nets)\"\n"
    $"($lab)HOMELAB_UNREACHABLE_METRIC=($HOMELAB_UNREACHABLE_METRIC)\n"
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let home_wired = $cfg.home_wired
    let bad = $cfg.home_gateways | where not ($it =~ $MAC)
    if ($bad | is-not-empty) { error make {msg: $"networkmanager: home_gateways has ($bad | str join ' '), not a mac"} }
    let homelab = homelab-env $cfg
    let online = $"nm-online -q --timeout=($ONLINE_TIMEOUT_S) || echo 'networkmanager: still offline' >&2"
    let restart = [sh -c $"systemctl restart NetworkManager.service && ($online)"]
    let dispatcher = {|src, name| file-copy $src $"($DISPATCHERS)/($name)" --mode 755 }
    [
        (if (which ModemManager | is-not-empty) and (has-modem) { unit-enable ModemManager.service --now } else { [] })
        # before the dispatchers: a missing policy means lockdown-tor, cutting this run's egress
        (file-text $"($NM)/untrusted-policy" $"($cfg.untrusted_policy)\n")
        (if $env.FORM_FACTOR? == "vm" { file-text $"($NM)/vm-guest" "" } else { [] })
        (if $homelab != null { file-text $"($NM)/homelab.env" $homelab } else { [] })
        (file-copy NetworkManager.conf $"($NM)/NetworkManager.conf" --then $restart)
        # NM's one auto wired profile serves every wired network, so a laptop's ethernet is never home (fail closed)
        (if $home_wired { file-copy home-wired.conf $"($NM)/conf.d/10-home-wired.conf" --then $restart } else { [] })
        (if $cfg.wake_on_lan {[
            (file-copy wake-on-lan.link /etc/systemd/network/90-wake-on-lan.link
                --then [sh -c "udevadm control --reload && udevadm trigger --action=add --subsystem-match=net"])
            (file-copy wake-on-lan.conf $"($NM)/conf.d/20-wake-on-lan.conf" --then $restart)
        ]} else { [] })
        (do $dispatcher home-network.nu 70-home-network)
        (do $dispatcher connectivity-check.nu 75-connectivity-check)
        (do $dispatcher homelab-routes.nu 80-homelab-routes)
        (do $dispatcher persona-dispatcher.nu 90-anonymous-persona)
        (step home ($home_wired | into string) ...$cfg.home_gateways)
        (if $cfg.wifi_radio == false {
            exec "wifi radio off" [sh -c $"nmcli radio wifi off && touch ($WIFI_OFF_MARK)"] --creates $WIFI_OFF_MARK
        } else { [] })
    ]
}

# home-gateways = the secrets' list (kept while locked) + the install answer (.local) + home_gateways
export def home [home_wired: string, ...gateways: string]: nothing -> nothing {
    let secrets = $env.DOTFILES_SECRETS? | default "/nonexistent"
    let secret_gateways = $"($NM)/home-gateways.secret"
    let secret_ssids = $"($NM)/home-ssids.secret"
    let local = $"($NM)/home-gateways.local"
    let file = $"($NM)/home-gateways"
    let macs = {|path| if ($path | path exists) { open --raw $path | lines | where $it =~ $MAC | str lowercase } else { [] } }

    let secret = $secrets | path join home-gateways
    if ($secret | path exists) {
        let lines = open --raw $secret | lines
        if ($lines | any {|l| not ($l =~ $MAC or $l =~ '^(#.*)?$') }) or not ($lines | any { $in =~ $MAC }) {
            error make {msg: $"networkmanager: home-gateways is not one mac address per line, keeping ($file)"}
        }
        $lines | where $it =~ $MAC | each { $"($in)\n" } | str join | save --force $secret_gateways
    }
    let wifi = $secrets | path join wifi
    if ($wifi | path exists) {
        open --raw $wifi | lines | each { split row "\t" | first } | where $it != "" | each { $"($in)\n" } | str join
        | save --force $secret_ssids
    }
    let option = $gateways | str lowercase
    let want = (do $macs $secret_gateways) ++ (do $macs $local) ++ $option | uniq
    $want | each { $"($in)\n" } | str join | save --force $file

    let ssids = if ($secret_ssids | path exists) { open --raw $secret_ssids | lines | where $it != "" } else { [] }
    let profiles = ^nmcli -g UUID,TYPE connection show | lines | parse "{uuid}:{type}"
    for p in ($profiles | where type == 802-11-wireless) {
        let mac = ^nmcli -g 802-11-wireless.cloned-mac-address connection show $p.uuid | str trim
        if (^nmcli -g 802-11-wireless.ssid connection show $p.uuid | str trim) in $ssids and $mac != "permanent" {
            ^nmcli connection modify $p.uuid 802-11-wireless.cloned-mac-address permanent ipv6.method auto
            if $p.uuid in (^nmcli -g UUID connection show --active | lines) { ^nmcli connection up $p.uuid | ignore }
        }
    }
    if $home_wired == "true" {
        for p in ($profiles | where type == 802-3-ethernet) { ^nmcli connection modify $p.uuid ipv6.method auto }
    }
    let connected = ^nmcli -g DEVICE,STATE device | lines | parse "{dev}:{state}" | where state == connected | get dev
    for dev in $connected { trusted-wifi-mac $dev $want $ssids }
    # 90 only lifts a lockdown on a link that just became home; 70 alone only refills the sets. Any other 90 up
    # restarts tor and portmaster, undoing an open portal or a stop by hand.
    for link in $connected {
        ^$"($DISPATCHERS)/70-home-network" $link up
        if not ($LOCKDOWN_MARKER | path exists) or not ($HOME_NETWORK | path exists) { continue }
        if $link not-in (open --raw $HOME_NETWORK | lines) { continue }
        let uuid = ^nmcli -g GENERAL.CON-UUID device show $link | str trim
        with-env {CONNECTION_UUID: $uuid} { ^$"($DISPATCHERS)/90-anonymous-persona" $link up }
    }
}

# A trusted gateway's wifi keeps the hardware mac (70-home-network needs it); untrusted gets random back.
def trusted-wifi-mac [dev: string, gateways: list<string>, ssids: list<string>]: nothing -> nothing {
    let uuid = ^nmcli -g GENERAL.CON-UUID device show $dev | str trim
    if $uuid == "" or (^nmcli -g connection.type connection show $uuid | str trim) != "802-11-wireless" { return }
    let gateway = ^ip -4 route show default dev $dev | lines | get --optional 0 | default "" | split row " " | get --optional 2
    if $gateway == null { return }
    let mac = ^ip neigh show $gateway dev $dev | parse --regex 'lladdr (?<mac>\S+)' | get --optional 0.mac | default ""
    let trusted = ($mac | str lowercase) in $gateways
    let permanent = (^nmcli -g 802-11-wireless.cloned-mac-address connection show $uuid | str trim) == "permanent"
    let ssid = ^nmcli -g 802-11-wireless.ssid connection show $uuid | str trim
    if $trusted and not $permanent {
        ^nmcli connection modify $uuid 802-11-wireless.cloned-mac-address permanent ipv6.method auto
    } else if not $trusted and $permanent and $ssid not-in $ssids {
        ^nmcli connection modify $uuid 802-11-wireless.cloned-mac-address ""
    } else { return }
    ^nmcli connection up $uuid | ignore
}
