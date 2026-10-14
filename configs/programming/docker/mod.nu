use module.nu *

export const meta = {packages: {pacman: [ctop docker docker-buildx docker-compose lazydocker trivy]}}

const MCP = {type: stdio, command: uvx, args: ["mcp-server-docker==0.3.0"]}

# forward policy lives in table inet fw: docker's own FORWARD drop would also cut libvirt and lxc bridges
export def system [cfg: record] {
    [
        (file-copy daemon.json /etc/docker/daemon.json)
        (unit-enable docker.socket)
        (unit-file docker-prune.service --enable)
    ]
}

# claude's docker mcp talks to /var/run/docker.sock, so only for a docker group member; membership is root without a
# password, never granted here (`sudo gpasswd -a $USER docker` opts in). id reads the group database, not this session
export def link [cfg: record] {
    let member = "docker" in (^id -nG $env.USER | str trim | split row " ")
    json-merge ($nu.home-dir | path join .claude.json) [
        (if $member { json-set [mcpServers docker] $MCP } else { json-delete [mcpServers docker] })
    ]
}
