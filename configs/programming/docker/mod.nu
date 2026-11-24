use module.nu *

export const meta = {packages: {pacman: [ctop docker docker-buildx docker-compose lazydocker trivy]}}

export const options = {
    prune_age_days: {type: int, default: 7, doc: "Age past which dangling images and build cache are pruned", label: "Prune age (days)", min: 1}
}

const HOURS_PER_DAY = 24
const DAYS_PER_WEEK = 7

export def link [cfg: record] {
    shell-aliases docker
}

export def system [cfg: record] {
    let days = $cfg.prune_age_days
    let age = if $days == $DAYS_PER_WEEK { "a week" } else { $"($days) days" }
    [
        # forwarding policy lives in inet fw: docker's own FORWARD drop would also cut libvirt and lxc bridges
        (file-copy config/daemon.json /etc/docker/daemon.json --then (unit-restart docker.service --if-running))
        (unit-enable docker.socket)
        (unit-file services/docker-prune.service --values {AGE: $age, AGE_HOURS: ($days * $HOURS_PER_DAY)} --enable)
    ]
}

# no docker MCP: its host mount is root-equivalent for anything that reaches it
