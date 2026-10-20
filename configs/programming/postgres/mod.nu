use module.nu *

export const meta = {packages: {pacman: [lazysql postgresql postgresql-libs sqlite sqlitebrowser]}}

# no package in arch or the aur; bump both from the release's checksums.txt
const VERSION = "1.1.0"
const SHA256 = "ca79e3054455b5505d3ac4ed4bc5d4cd074a57f108b8fe9ddcd3e24d16c5452a"
const URL = $"https://github.com/pgEdge/pgedge-postgres-mcp/releases/download/v($VERSION)/pgedge-postgres-mcp-server_($VERSION)_linux_x86_64.tar.gz"
const BINARY = "pgedge-postgres-mcp"
const DATA = "/var/lib/postgres/data"

export def system [cfg: record] {
    let admins = open /etc/group | lines | parse "{name}:{x}:{gid}:{members}" | where name == wheel
        | get --optional 0.members | default "" | split row "," | where $it =~ '^[a-z_][a-z0-9_-]*$'
    let init = $"cd / && install -d -o postgres -g postgres -m 700 ($DATA) && runuser -u postgres -- initdb -D ($DATA) --encoding=UTF8 --locale=C.UTF-8 --auth-local=peer --auth-host=scram-sha-256 > /dev/null"
    [
        (exec initdb [sh -c $init] --creates ($DATA | path join PG_VERSION))
        # the postgres MCP connects to it: initdb alone leaves the server off on every machine
        (unit-enable postgresql.service --now)
        ($admins | each {|admin| step role-ensure $admin })
    ]
}

def sql [query: string]: nothing -> string {
    # postgres can not read the module dir
    cd /
    if (do { ^systemctl is-active --quiet postgresql } | complete).exit_code == 0 {
        ^runuser -u postgres -- psql -XqtA -v ON_ERROR_STOP=1 -c $query
    } else {
        $query | ^runuser -u postgres -- postgres --single -c log_checkpoints=off -D $DATA postgres
    }
}

export def role-ensure [admin: string]: nothing -> nothing {
    if not (sql $"SELECT 'yes' FROM pg_roles WHERE rolname = '($admin)'" | str contains yes) {
        sql $"CREATE ROLE \"($admin)\" LOGIN CREATEDB" | ignore
    }
    if not (sql $"SELECT 'yes' FROM pg_database WHERE datname = '($admin)'" | str contains yes) {
        sql $"CREATE DATABASE \"($admin)\" OWNER \"($admin)\"" | ignore
    }
}

export def link [cfg: record] {
    if (which postgres | is-empty) { return [] }
    let root = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join pgedge-postgres-mcp
    let old = if ($root | path exists) { ls $root | where type == dir and ($it.name | path basename) != $VERSION | get name } else { [] }
    [
        (fetch-file $URL $SHA256 ($root | path join $VERSION $BINARY) --mode 755 --extract $BINARY)
        ($old | each {|dir| exec $"drop ($dir)" [rm -rf $dir] })
        (link-commands postgres-mcp.nu)
        (json-merge ($nu.home-dir | path join .claude.json) [
            (json-set [mcpServers postgres-mcp] {type: stdio, command: ($nu.home-dir | path join .local bin postgres-mcp), args: [], env: {}})
        ])
    ]
}
