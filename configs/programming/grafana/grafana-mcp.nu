#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname --num-levels 4
const LAB_SCHEMA = 1

# The homelab's interface for desktop clients, written by its sync.sh (homelab src/modules/lab-export.nix).
def lab-json []: nothing -> path {
    $env.HOMELAB_DIR? | default ($nu.home-dir | path join projects homelab) | path join src generated lab.json
}

def grafana-url []: nothing -> string {
    let file = lab-json
    let lab = try { open $file } catch { null }
    if ($lab | describe) !~ '^record' { error make --unspanned {msg: $"grafana-mcp: ($file) is missing or not json"} }
    if $lab.schema? != $LAB_SCHEMA { error make --unspanned {msg: $"grafana-mcp: ($file) has schema ($lab.schema? | to nuon), wants ($LAB_SCHEMA)"} }
    let url = $lab.monitoring?.grafana?
    if ($url | describe) != "string" { error make --unspanned {msg: $"grafana-mcp: ($file) names no monitoring.grafana"} }
    $url
}

def --wrapped main [...args: string]: nothing -> nothing {
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    load-env {
        GRAFANA_URL: (grafana-url)
        GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE: ($REPO | path join configs secrets keys grafana-mcp-token)
        GRAFANA_USAGE_STATS: disabled
        DO_NOT_TRACK: "1"
    }
    (exec ($data | path join mcp-grafana mcp-grafana) -t stdio --usage-stats disabled
        --disable-write --disable-admin --disable-docs ...$args)
}
