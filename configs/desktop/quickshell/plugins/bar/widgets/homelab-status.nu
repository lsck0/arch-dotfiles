#!/usr/bin/env -S nu --no-config-file

const LAB_RELATIVE = "src/generated/lab.json"
const LAB_SCHEMA = 1
const SEEN = "6h"
const CLIENT_WINDOW = "24h"
const CLIENT_ROWS = 8
const UNKNOWN_VM_ID = 100000
const ORDER_UNLISTED = 1000
const WEB_PORTS = [80 443]
const STATUS_CLASSES = [2xx 3xx 4xx 5xx]
const FETCH_TIMEOUT = 5sec
const PROBE_TIMEOUT = 3sec
const GIB = 1073741824
const AGENT_FAMILY = (
    '{{ if or (contains "bot" .ua) (contains "Bot" .ua) (contains "crawl" .ua) (contains "spider" .ua) }}bot'
    + '{{ else if contains "Edg/" .ua }}Edge'
    + '{{ else if contains "Chrome/" .ua }}Chrome'
    + '{{ else if contains "Firefox/" .ua }}Firefox'
    + '{{ else if contains "Safari/" .ua }}Safari'
    + '{{ else if or (contains "Go-http" .ua) (contains "connect-go" .ua) }}Go'
    + '{{ else if or (contains "curl" .ua) (contains "Wget" .ua) }}curl'
    + '{{ else }}other{{ end }}'
)

def fetch [base: string, path: string, expr: string]: nothing -> record {
    http get --max-time $FETCH_TIMEOUT $"($base)($path)?({query: $expr} | url build-query)"
}

def source-load [lab: record]: nothing -> record {
    let guests = $lab.guests | transpose key guest | each {|g|
        {
            id: ($g.key | into int)
            name: ($g.guest.name | str replace -r $"^\\d+-\(?:($g.guest.zone)-)?" '')
            type: $g.guest.zone
            ip: $g.guest.ip
            enabled: $g.guest.enabled
            onDemand: ($g.guest.enabled == onDemand)
        }
    }
    let urls = $lab.routes | transpose route r | where r.protocol == http | each {|route|
        let vm = $guests | where id == $route.r.vmid | get 0?
        if $vm != null {
            {id: $vm.id, named: ($route.route != $vm.name), web: ($route.r.port not-in $WEB_PORTS), route: $route.route, host: $route.r.host}
        }
    } | sort-by named web route | uniq-by id | each {|r| {id: $r.id, url: $"https://($r.host)"} }
    let monitoring = $lab.monitoring
    let dashboard = $monitoring.grafana + $monitoring.dashboard
    let monitor_ip = $monitoring.prometheus | url parse | get host
    let vms = $guests | each {|vm|
        let url = $urls | where id == $vm.id | get 0?.url | default ""
        $vm | insert url (if $vm.ip == $monitor_ip { $dashboard } else { $url })
    }
    let by_ip = $vms | where ip != null and ip != "" | each {|vm| [$vm.ip $vm] } | into record
    let router = $vms | where type == router | get 0?
    let by_ip = if $router == null { $by_ip } else {
        $lab.zones | values | reduce --fold $by_ip {|zone, acc| $acc | upsert $zone.router $router }
    }
    let named = {|name| $vms | where name == $name | get 0? }
    let nas = do $named nas
    {
        infra: ($lab.infra | select name href ping | each { default "" href | default "" ping })
        loki: $monitoring.loki
        ingress: $monitoring.accessLog
        domain: $lab.domain
        by_ip: $by_ip
        subnets: ($lab.zones | items {|name, zone| [$name ($zone.subnet | str replace -r '\.\d+/\d+$' '')] } | into record)
        host_ip: $lab.proxmox.ip
        prometheus: $monitoring.prometheus
        nas_ip: ($nas.ip? | default "")
        links: {
            homepage: (do $named homepage | get -o url | default "")
            dashboard: $dashboard
            alerts: $"($monitoring.grafana)/alerting/list"
            proxmox: $lab.proxmox.url
            nas: ($nas.url? | default "")
        }
    }
}

def vm-for [instance: string, src: record]: nothing -> record {
    let ip = $instance | str replace -r ':[^:]*$' ''
    if $ip == $src.host_ip {
        return {id: 0, name: proxmox, url: $src.links.proxmox, onDemand: false, type: router}
    }
    let vm = $src.by_ip | get -o $ip
    if $vm != null { return $vm }
    let zone = $src.subnets | transpose zone prefix | where {|z| $ip | str starts-with $"($z.prefix)." } | get 0?.zone
    {id: $UNKNOWN_VM_ID, name: $ip, url: "", onDemand: false, type: ($zone | default "")}
}

def count-human []: number -> string {
    let n = $in
    if $n < 1000 { $n | into int | into string } else if $n < 10000 {
        $"($n / 1000 | into string --decimals 1)k"
    } else if $n < 1000000 { $"($n / 1000 | into string --decimals 0)k" } else {
        $"($n / 1000000 | into string --decimals 1)M"
    }
}

def bars [scale?: number]: list<any> -> list<any> {
    let rows = $in
    let top = $scale | default ($rows.count | append 0 | math max)
    $rows | each {|r| {name: $r.name, count: ($r.count | count-human), pct: (if $top > 0 { 100 * $r.count / $top | math round | into int } else { 0 })} }
}

def clients [src: record]: nothing -> record {
    if ($src.loki | is-empty) or ($src.ingress | is-empty) { return {} }
    let stream = $'{job="traefik-access", host="($src.ingress)"}'
    let instant = {|expr|
        let body = fetch $src.loki /loki/api/v1/query $expr
        if $body.status? == success { $body.data.result } else { [] }
    }
    let ranked = {|expr, label, fallback|
        do $instant $expr | each {|r| {name: ($r.metric | get -o $label | default -e $fallback), count: ($r.value.1 | into float)} }
        | sort-by count --reverse | first $CLIENT_ROWS | bars
    }
    let countries = do $ranked $"topk\(($CLIENT_ROWS), sum by \(country) \(count_over_time\(($stream)[($CLIENT_WINDOW)])))" country direct
    let agents = (do $ranked
        $"topk\(($CLIENT_ROWS), sum by \(agent) \(count_over_time\(($stream) | json ua=`[\"request_User-Agent\"]` | label_format agent=`($AGENT_FAMILY)` [($CLIENT_WINDOW)])))"
        agent other)
    let suffix = if ($src.domain | is-empty) { "" } else { $".($src.domain)" }
    let hosts = do $ranked $"topk\(($CLIENT_ROWS), sum by \(h) \(count_over_time\(($stream) | json h=\"RequestHost\" [($CLIENT_WINDOW)])))" h direct
    | update name {|h|
        if $suffix != "" and ($h.name | str ends-with $suffix) { $h.name | str replace $suffix "" } else if $h.name =~ '^\d' { "by address" } else { $h.name }
    }
    let by_status = do $instant $"sum by \(status) \(count_over_time\(($stream)[($CLIENT_WINDOW)]))" | each {|r|
        let code = $r.metric.status? | default ""
        {class: (if $code =~ '^\d' { $"($code | str substring 0..0)xx" } else { "?" }), count: ($r.value.1 | into float)}
    } | group-by class | transpose class rows | each {|g| [$g.class ($g.rows.count | math sum)] } | into record
    let total = $by_status | values | append 0.0 | math sum
    let visitors = do $instant $"count\(count by \(ip) \(count_over_time\(($stream) | json ip=\"ClientHost\" [($CLIENT_WINDOW)])))" | get 0?.value.1 | default 0 | into float
    let traffic = [[name count]; [requests $total] [visitors $visitors]]
    | append ($STATUS_CLASSES | each {|c| {name: $c, count: ($by_status | get -o $c | default 0.0)} })
    | bars $total
    let traffic = $traffic | first 2 | update pct 0 | append ($traffic | skip 2)
    {window: $CLIENT_WINDOW, countries: $countries, agents: $agents, hosts: $hosts, traffic: $traffic}
}

def sample [src: record]: nothing -> record {
    if ($src.by_ip | is-empty) or ($src.prometheus | is-empty) { return {ok: false, error: source} }
    let query = {|expr| fetch $src.prometheus /api/v1/query $expr | get -o data.result | default [] | each {|r| {metric: $r.metric, value: ($r.value.1 | into float)} } }
    let scalar = {|expr| do $query $expr | get 0?.value }
    let now_s = (date now | into int) / 1_000_000_000
    let seen = 'up{job="homelab-node-exporter"} and on(instance) max_over_time(up{job="homelab-node-exporter"}[' + $SEEN + ']) > 0'
    let services = do $query $seen | reduce --fold {} {|row, acc|
        let vm = vm-for ($row.metric.instance? | default "") $src
        if $vm.enabled? == "false" or ($row.value != 1 and $vm.id == $UNKNOWN_VM_ID) { return $acc }
        let key = $"($vm.id)/($vm.name)"
        let up = ($acc | get -o $key | get -o up | default false) or $row.value == 1
        $acc | upsert $key ($vm | select id name url onDemand | insert group (if $vm.type? == router { "infra" } else { $vm.type? | default -e internal }) | insert up $up)
    }
    let services = $src.infra | enumerate | reduce --fold $services {|item, acc|
        let infra = $item.item
        let ip = $infra.ping | default -e $infra.href | parse -r '^\w+://(?<ip>[^/:]+)' | get 0?.ip
        let vm = if $ip == null { null } else { vm-for $ip $src }
        let key = if $vm != null and ($"($vm.id)/($vm.name)" in $acc) { $"($vm.id)/($vm.name)" } else { $"infra/($infra.name)" }
        let known = if $key in $acc { $acc | get $key } else {
            {
                id: -1, url: "", onDemand: false
                up: (if ($infra.ping | is-empty) { null } else {
                    try { http get --full --allow-errors --insecure --max-time $PROBE_TIMEOUT $infra.ping | ignore; true } catch { false }
                })
            }
        }
        $acc | upsert $key ($known | upsert name ($infra.name | str lowercase) | upsert group infra | upsert order $item.index
            | upsert url ($infra.href | default -e $known.url))
    }
    let target_name = {|target|
        let vmid = $target | parse -r '^vm-(?<id>\d+)$' | get 0?.id
        let vm = if $vmid != null {
            $src.by_ip | values | where id == ($vmid | into int) | get 0?
        } else if $target =~ '^\d+\.\d+\.\d+\.\d+' { vm-for $target $src }
        if $vm == null { {name: $target, disabled: false} } else { {name: $vm.name, disabled: ($vm.enabled? == "false")} }
    }
    let alerts = try { do $query homelab_alert_firing } catch { [] } | each {|alert|
        let target = if ($alert.metric.target? | is-empty) { {name: "", disabled: false} } else { do $target_name $alert.metric.target }
        if not $target.disabled {
            {name: ($alert.metric.alertname? | default alert), target: $target.name, minutes: ([0 (($now_s - $alert.value) / 60 | into int)] | math max)}
        }
    } | sort-by minutes
    let services = $services | values | sort-by {|s| $s.order? | default $ORDER_UNLISTED } id name

    let host = $'instance="($src.host_ip):9100"'
    let nas = $'instance="($src.nas_ip):9100",mountpoint="/"'
    let mem_total = do $scalar $"node_memory_MemTotal_bytes{($host)}"
    let mem_avail = do $scalar $"node_memory_MemAvailable_bytes{($host)}"
    let nas_free = do $scalar $"node_filesystem_avail_bytes{($nas)}"
    let nas_size = do $scalar $"node_filesystem_size_bytes{($nas)}"
    let backup = do $scalar "max(homelab_backup_last_success_timestamp_seconds)"
    let rounded = {|value, digits| if $value == null { null } else { $value | math round --precision $digits } }
    let rps = {|zone|
        let pattern = ($src.subnets | get $zone | str replace -a '.' '\\.') + '\\..*'
        do $rounded (do $scalar $"sum\(rate\(traefik_entrypoint_requests_total{instance=~\"($pattern)\"}[5m]))" | default 0) 2
    }
    {
        ok: true
        links: $src.links
        services: $services
        alerts: $alerts
        host: {
            cpuPct: (do $rounded (do $scalar $"100 * \(1 - avg\(rate\(node_cpu_seconds_total{mode=\"idle\",($host)}[5m])))") 0)
            memUsedGb: (if ($mem_total | default 0) != 0 and $mem_avail != null { do $rounded (($mem_total - $mem_avail) / $GIB) 1 })
            memTotalGb: (if ($mem_total | default 0) != 0 { do $rounded ($mem_total / $GIB) 0 })
            tempC: (do $rounded (do $scalar $"max\(node_hwmon_temp_celsius{($host)})") 0)
            uptimeH: (let uptime_s = do $scalar $"node_time_seconds{($host)} - node_boot_time_seconds{($host)}"; if $uptime_s != null { do $rounded ($uptime_s / 3600) 0 })
        }
        storage: {
            nasFreeGb: (if $nas_free != null { do $rounded ($nas_free / $GIB) 0 })
            nasTotalGb: (if $nas_size != null { do $rounded ($nas_size / $GIB) 0 })
            disksHealthy: (let healthy = do $scalar "sum(smartmon_device_smart_healthy)"; if $healthy != null { $healthy | into int })
            disksTotal: (let total = do $scalar "count(smartmon_device_smart_healthy)"; if $total != null { $total | into int })
            nvmeWearPct: (let wear = do $scalar "max(nvme_percentage_used_ratio)"; if $wear != null { do $rounded ($wear * 100) 0 })
            backupAgeMin: (if ($backup | default 0) != 0 { ($now_s - $backup) / 60 | into int })
        }
        traffic: {
            internalRps: (if internal in $src.subnets { do $rps internal })
            externalRps: (if external in $src.subnets { do $rps external })
            errorRps: (do $rounded (do $scalar 'sum(rate(traefik_entrypoint_requests_total{code=~"5.."}[5m]))' | default 0) 2)
        }
        clients: (try { clients $src } catch { {} })
    }
}

def main [interval_s: int = 30] {
    let lab_path = $env.HOMELAB_DIR? | default ($nu.home-dir | path join projects homelab) | path join $LAB_RELATIVE
    mut modified: any = null
    mut src = {by_ip: {}, prometheus: ""}
    loop {
        let stamp = try { ls -l $lab_path | get 0.modified } catch { null }
        if $stamp == null or $stamp != $modified {
            let lab = try { open $lab_path } catch { null }
            $src = if ($lab | describe) =~ '^record' and $lab.schema? == $LAB_SCHEMA { source-load $lab } else { {by_ip: {}, prometheus: ""} }
            $modified = $stamp
        }
        let line = try { sample $src } catch {|error| {ok: false, error: $error.msg} }
        print ($line | to json -r)
        sleep ($interval_s * 1sec)
    }
}
