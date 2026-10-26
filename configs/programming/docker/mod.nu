use module.nu *

export const meta = {packages: {pacman: [ctop docker docker-buildx docker-compose lazydocker trivy uv]}}

export def system [cfg: record] {
    [
        # forwarding policy lives in inet fw: docker's own FORWARD drop would also cut libvirt and lxc bridges
        (file-copy daemon.json /etc/docker/daemon.json --then [systemctl try-restart docker.service])
        (unit-enable docker.socket)
        (unit-file docker-prune.service --enable)
    ]
}

# no MCP server here: mcp-server-docker's typical mount (-v /:/host) gives root-equivalent host access to anything
# that can reach it, breaking "agents never reach root" even for a docker-group member
