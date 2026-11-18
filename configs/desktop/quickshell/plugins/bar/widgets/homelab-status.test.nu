#!/usr/bin/env -S nu --no-config-file
# source-load finds the nas and the dashboard by their lab-wide role, never by a guest's name: the link is the role
# holder's route of the link's name, else the holder's own url, else empty when no guest holds the role.
# minecraft-from shapes the minecraft series into one row per server: the current phase, worst TPS from the slowest
# dimension or else the mean tick, mc-metrics readings only while they answer.
use homelab-status.nu [minecraft-from source-load]

const ROUTE = {path: "/", zone: internal, protocol: http, app: null, health: "/", onion: null, clearnet: true}
const LAB = {
    schema: 1
    domain: lab.test
    router: "192.0.2.1"
    zones: {internal: {subnet: "10.9.0.0/24", router: "10.9.0.1", ingress: 7}}
    guests: {
        "7": {name: "7-internal-core", zone: internal, ip: "10.9.0.7", powered: true, idle: null, enabled: "true", roles: [dashboard nas]}
        "8": {name: "8-internal-nas", zone: internal, ip: "10.9.0.8", powered: true, idle: null, enabled: "true", roles: []}
    }
    routes: {}
    infra: []
    proxmox: {ip: "192.0.2.2", url: "https://proxmox.lab.test"}
    monitoring: {prometheus: "http://10.9.0.7:9090", loki: "", grafana: "https://grafana.lab.test", dashboard: "/d/x", accessLog: ""}
}

const GIB = 1073741824
const MC_EMPTY = {phase: [], players: [], dimensionTps: [], tickMean: [], memUsed: [], memLimit: [], metricsUp: [], startFailures: []}

def fail [msg: string] { error make {msg: $"homelab-status.test: ($msg)"} }

def series [rows: list<list<any>>]: nothing -> list<record> {
    $rows | each {|r| {metric: {server: $r.0}, value: ($r.1 | into float)} }
}

def phases [current: record]: nothing -> list<record> {
    $current | items {|server, phase|
        [running sleeping] | append $phase | uniq | each {|p| {metric: {server: $server, phase: $p}, value: (if $p == $phase { 1.0 } else { 0.0 })} }
    } | flatten
}

def minecraft-cases [] {
    let running = {
        phase: (phases {atm: running, vanilla: sleeping})
        players: (series [[atm 3] [vanilla 0]])
        dimensionTps: (series [[atm 19.87]])
        tickMean: (series [[atm 30]])
        memUsed: (series [[atm (6 * $GIB)]])
        memLimit: (series [[atm (12 * $GIB)]])
        metricsUp: (series [[atm 1]])
        startFailures: (series [[atm 0] [vanilla 0]])
    }
    let atm = {name: atm, phase: running, players: 3, tps: 19.9, memUsedBytes: (6.0 * $GIB), memLimitBytes: (12.0 * $GIB), startFailures: 0}
    let asleep = {|name| {name: $name, phase: sleeping, players: 0, tps: null, memUsedBytes: null, memLimitBytes: null, startFailures: 0} }
    let cases = [
        [name series want];
        [empty $MC_EMPTY []]
        [all-sleeping ($MC_EMPTY | merge {phase: (phases {vanilla: sleeping, atm: sleeping})}) [(do $asleep atm) (do $asleep vanilla)]]
        [running-first $running [$atm (do $asleep vanilla)]]
        [tick-without-dimensions ($running | merge {phase: (phases {vanilla: running}), dimensionTps: [], tickMean: (series [[vanilla 62.5]]), metricsUp: (series [[vanilla 1]])})
            [{name: vanilla, phase: running, players: 0, tps: 16.0, memUsedBytes: null, memLimitBytes: null, startFailures: 0}]]
        [tick-capped ($running | merge {dimensionTps: [], tickMean: (series [[atm 12]])}) [($atm | update tps 20) (do $asleep vanilla)]]
        [metrics-down ($running | merge {metricsUp: (series [[atm 0]])})
            [($atm | merge {tps: null, memUsedBytes: null, memLimitBytes: null}) (do $asleep vanilla)]]
        [start-failure ($MC_EMPTY | merge {phase: (phases {smeadcraft: starting}), startFailures: (series [[smeadcraft 0.4]])})
            [((do $asleep smeadcraft) | merge {phase: starting, startFailures: 1})]]
        [no-current-phase ($MC_EMPTY | merge {phase: [{metric: {server: atm, phase: running}, value: 0.0}]}) [((do $asleep atm) | update phase unknown)]]
    ]
    for c in $cases {
        let got = minecraft-from $c.series
        if $got != $c.want { fail $"minecraft ($c.name): ($got | to nuon)" }
    }
}

def main [] {
    let routes = {
        homepage: ($ROUTE | merge {host: home.lab.test, vmid: 7, port: 8086})
        nas: ($ROUTE | merge {host: nas.lab.test, vmid: 7, port: 8085})
        files: ($ROUTE | merge {host: files.lab.test, vmid: 8, port: 8080})
    }
    let cases = [
        [name routes guests want_homepage want_nas want_nas_ip];
        [routes-of-holder $routes $LAB.guests "https://home.lab.test" "https://nas.lab.test" "10.9.0.7"]
        [holder-url-without-route ($routes | reject homepage) $LAB.guests "https://grafana.lab.test/d/x" "https://nas.lab.test" "10.9.0.7"]
        [no-holder $routes ($LAB.guests | update "7".roles []) "" "" ""]
    ]
    for c in $cases {
        let src = source-load ($LAB | update routes $c.routes | update guests $c.guests)
        let got = [$src.links.homepage $src.links.nas $src.nas_ip]
        if $got != [$c.want_homepage $c.want_nas $c.want_nas_ip] { fail $"($c.name): ($got | to nuon)" }
    }
    minecraft-cases
}
