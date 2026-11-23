use module.nu *

export const meta = {packages: {pacman: [act podman]}}

# act talks to rootless podman's socket through its shell alias: no root daemon, no docker group
export def link [cfg: record] {
    [
        (unit-enable podman.socket --now)
        # the store only grows otherwise: every act run and image build leaves its layers in ~/.local/share/containers
        (unit-file podman-prune.service)
        (unit-timer podman-prune.timer "Prune rootless podman images weekly" --calendar weekly
            --delay 1h --enable --now)
        (shell-aliases act)
        (file-copy actrc (xdg config act actrc))
    ]
}
