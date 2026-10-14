#!/usr/bin/env -S nu --no-config-file
# claude's grafana entry (mod.nu) runs this: mcp-grafana over stdio against the homelab grafana, whose url comes from
# the homelab's desktop export (src/generated/lab.json) and whose service account token comes from secrets. read only:
# no write or admin tools, no docs lookups on grafana.com, no usage stats

const REPO = path self | path expand | path dirname --num-levels 4

def --wrapped main [...args: string]: nothing -> nothing {
    let homelab = $env.HOMELAB_DIR? | default ($nu.home-dir | path join projects homelab)
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    load-env {
        GRAFANA_URL: (open ($homelab | path join src generated lab.json) | get monitoring.grafana)
        GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE: ($REPO | path join secrets grafana-mcp-token)
        GRAFANA_USAGE_STATS: disabled
        DO_NOT_TRACK: "1"
    }
    (exec ($data | path join mcp-grafana mcp-grafana) -t stdio --usage-stats disabled
        --disable-write --disable-admin --disable-docs ...$args)
}
