#!/usr/bin/env -S nu --no-config-file
# pgedge's postgres mcp server (mod.nu installs it) on this user's own role and database in the local cluster, for
# claude's postgres-mcp entry. the server takes no unix socket path for a host, so it logs in over 127.0.0.1 with scram,
# reading the password from ~/.pgpass. that password is made here, per machine, and set on the role over the socket,
# where peer auth already lets this user in: nothing to keep in secrets, nothing in ~/.claude.json. stdio, no port;
# every query runs in a read-only transaction (no database here sets allow_writes)

const HOST = "127.0.0.1"
const PORT = 5432
const SOCKET = "/run/postgresql"
const PASSWORD_BYTES = 24

def login-works [host: string]: nothing -> bool {
    (with-env {PGHOST: $host} { ^psql -XqtAw -c 'SELECT 1' | complete }).exit_code == 0
}

def main []: nothing -> nothing {
    let pgpass = $nu.home-dir | path join .pgpass
    let prefix = $"($HOST):($PORT):*:($env.USER):"
    load-env {
        PGHOST: $HOST, PGPORT: ($PORT | into string), PGUSER: $env.USER, PGDATABASE: $env.USER, PGSSLMODE: disable
    }
    # one line per host, port, database and user; never touches another
    let entries = if ($pgpass | path exists) { open --raw $pgpass | lines } else { [] }
    if not ($entries | any { str starts-with $prefix }) {
        if not ($pgpass | path exists) { touch $pgpass; ^chmod 600 $pgpass }
        $"($prefix)(^openssl rand -hex $PASSWORD_BYTES)\n" | save --append $pgpass
    }
    ^chmod 600 $pgpass
    # a fresh role, or a fresh ~/.pgpass, is out of step: the socket login sets the role's password from the file,
    # through stdin so it never shows in a process list. a stopped cluster fails both logins and the server reports it
    # per query
    if not (login-works $HOST) and (login-works $SOCKET) {
        let password = open --raw $pgpass | lines | where { str starts-with $prefix } | first
            | str substring ($prefix | str length)..
        let sql = $"ALTER ROLE CURRENT_USER PASSWORD '($password)';"
        with-env {PGHOST: $SOCKET} { $sql | ^psql -Xqw -v ON_ERROR_STOP=1 | ignore }
    }
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    let servers = glob ($data | path join pgedge-postgres-mcp * pgedge-postgres-mcp) | sort
    if ($servers | is-empty) { print -e "postgres-mcp: no server installed, run dot apply"; exit 1 }
    # -config names no file, so an /etc/pgedge config is never picked up; the database comes from the PG* variables
    exec ($servers | last) -config /dev/null
}
