#!/usr/bin/env -S nu --no-config-file
# source-load finds the nas and the dashboard by their lab-wide role, never by a guest's name: the link is the role
# holder's route of the link's name, else the holder's own url, else empty when no guest holds the role.
use homelab-status.nu [source-load]

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

def fail [msg: string] { error make {msg: $"homelab-status.test: ($msg)"} }

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
}
