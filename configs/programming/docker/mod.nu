use module.nu *

export const meta = {packages: {pacman: [ctop docker docker-buildx docker-compose lazydocker trivy]}}

const MCP = {type: stdio, command: uvx, args: ["mcp-server-docker==0.3.0"]}

# forward policy lives in table inet fw: docker's own FORWARD drop would also cut libvirt and lxc bridges
export def system [cfg: record] {
    [
        (file-copy daemon.json /etc/docker/daemon.json --then [systemctl try-restart docker.service])
        (unit-enable docker.socket)
        (unit-file docker-prune.service --enable)
    ]
}

# docker group membership is root without a password, never granted here; id reads the group db, not this session
export def link [cfg: record] {
    let member = "docker" in (^id -nG $env.USER | str trim | split row " ")
    json-merge ($nu.home-dir | path join .claude.json) [
        (if $member { json-set [mcpServers docker] $MCP } else { json-delete [mcpServers docker] })
    ]
}
