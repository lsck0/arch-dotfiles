#!/usr/bin/env -S nu --no-config-file
# the server takes no socket path for a host: scram over 127.0.0.1 with a per-machine password in ~/.pgpass

const HOST = "127.0.0.1"
const PORT = 5432
const SOCKET = "/run/postgresql"
const PASSWORD_BYTES = 24

def login-works [host: string]: nothing -> bool {
    (with-env {PGHOST: $host} { ^psql -XqtAw -c 'SELECT 1' | complete }).exit_code == 0
}

def main []: nothing -> nothing {
    let pgpass = $env.PGPASSFILE? | default ($nu.home-dir | path join .local share pgpass)
    let prefix = $"($HOST):($PORT):*:($env.USER):"
    load-env {
        PGHOST: $HOST, PGPORT: ($PORT | into string), PGUSER: $env.USER, PGDATABASE: $env.USER, PGSSLMODE: disable
    }
    let entries = if ($pgpass | path exists) { open --raw $pgpass | lines } else { [] }
    if not ($entries | any { str starts-with $prefix }) {
        if not ($pgpass | path exists) { touch $pgpass; ^chmod 600 $pgpass }
        $"($prefix)(^openssl rand -hex $PASSWORD_BYTES)\n" | save --append $pgpass
    }
    ^chmod 600 $pgpass
    # a fresh role or ~/.pgpass is out of step: set it over the socket, through stdin so it stays out of ps
    if not (login-works $HOST) and (login-works $SOCKET) {
        let password = open --raw $pgpass | lines | where { str starts-with $prefix } | first
            | str substring ($prefix | str length)..
        let sql = $"ALTER ROLE CURRENT_USER PASSWORD '($password)';"
        with-env {PGHOST: $SOCKET} { $sql | ^psql -Xqw -v ON_ERROR_STOP=1 | ignore }
    }
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    let servers = glob ($data | path join pgedge-postgres-mcp * pgedge-postgres-mcp)
        | sort-by {|p| $p | path dirname | path basename | split row . | each { into int } }
    if ($servers | is-empty) { print -e "postgres-mcp: no server installed, run dot apply"; exit 1 }
    exec ($servers | last) -config /dev/null
}
