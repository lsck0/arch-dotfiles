use module.nu *

export const meta = {packages: {pacman: [act podman]}}

# act talks to rootless podman's socket: no root daemon, no docker group
export def link [cfg: record] {
    [
        (unit-enable podman.socket --now)
        # the store only grows otherwise: every act run and image build leaves its layers in ~/.local/share/containers
        (unit-file podman-prune.service)
        (unit-file podman-prune.timer --enable --now)
        (files-into (xdg config environment.d) docker-host.conf)
        (file-copy actrc (xdg config act actrc))
    ]
}
