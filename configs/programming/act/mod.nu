use module.nu *

export const meta = {packages: {pacman: [act podman]}}

# act talks to rootless podman's socket: no root daemon, no docker group
export def link [cfg: record] {
    [
        (unit-enable podman.socket --now)
        (files-into (xdg config environment.d) docker-host.conf)
        (file-copy actrc (xdg config act actrc))
    ]
}
