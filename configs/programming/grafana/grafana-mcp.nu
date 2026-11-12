#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib homelab.nu) [homelab-lab-load]
use ($REPO | path join scripts lib state.nu) [xdg]

def grafana-url []: nothing -> string {
    let lab = homelab-lab-load
    let url = $lab | get --optional monitoring.grafana
    if ($url | describe) != "string" {
        error make --unspanned {msg: "grafana-mcp: the homelab's lab.json is missing, of another schema or names no monitoring.grafana"}
    }
    $url
}

def --wrapped main [...args: string]: nothing -> nothing {
    load-env {
        GRAFANA_URL: (grafana-url)
        GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE: ($REPO | path join configs secrets keys grafana-mcp-token)
        GRAFANA_USAGE_STATS: disabled
        DO_NOT_TRACK: "1"
    }
    (exec (xdg data mcp-grafana mcp-grafana) -t stdio --usage-stats disabled
        --disable-write --disable-admin --disable-docs ...$args)
}
