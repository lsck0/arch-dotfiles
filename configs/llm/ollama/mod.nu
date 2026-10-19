use module.nu *

export const meta = {packages: {pacman: [ollama]}}

const RESTART = [systemctl try-restart ollama.service]

export def link [cfg: record] {
    link-commands ollama-ensure-models.nu
}

# copies, not links: pid1 loads units and drop-ins before /home mounts
export def system [cfg: record] {
    [
        (unit-file ollama-proxy.service)
        (unit-file ollama.socket --enable --now)
        (dropin ollama.service listen.conf --then $RESTART)
        (dropin ollama.service keep-alive.conf --then $RESTART)
        (dropin ollama.service hardening.conf --then $RESTART)
        (dropin ollama.service gpu.conf --then $RESTART)
    ]
}
