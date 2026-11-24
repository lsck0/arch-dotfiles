use module.nu *

export const meta = {packages: {pacman: [act podman]}}

export const options = {
    container_memory: {type: string, default: "12g", doc: "Memory cap of each job container (podman --memory)", label: "Job memory"}
    container_cpus: {type: int, default: 4, doc: "CPUs of each job container", label: "Job CPUs", min: 1}
    prune_age_days: {type: int, default: 30, doc: "Age past which an unused tagged image is pruned", label: "Prune age (days)", min: 1}
}

const HOURS_PER_DAY = 24

# act talks to rootless podman's socket through its shell alias: no root daemon, no docker group
export def link [cfg: record] {
    [
        (unit-enable podman.socket --now)
        # the store only grows otherwise: every act run and image build leaves its layers in ~/.local/share/containers
        (unit-file services/podman-prune.service --values {AGE_DAYS: $cfg.prune_age_days, AGE_HOURS: ($cfg.prune_age_days * $HOURS_PER_DAY)})
        (unit-timer podman-prune.timer "Prune rootless podman images weekly" --calendar weekly
            --delay 1h --enable --now)
        (shell-aliases act)
        (file-render config/actrc (xdg config act actrc) {MEMORY: $cfg.container_memory, CPUS: $cfg.container_cpus})
    ]
}
