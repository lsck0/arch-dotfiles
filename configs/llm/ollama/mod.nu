use module.nu *

export const meta = {packages: {pacman: [ollama]}}

const RESTART = [systemctl try-restart ollama.service]

# models are pulled lazily on first use, never here: keeps an apply off the GB download path
export def link [cfg: record] {
    link-commands ollama-ensure-models.nu
}

# socket-activated like vllm: clients (alpaca, System One, the cli) reach 11434 without a resident daemon. copies, not
# links: pid1 loads units and drop-ins before /home mounts
export def system [cfg: record] {
    [
        (unit-file ollama-proxy.service)
        (unit-file ollama.socket --enable --now)
        (dropin ollama.service listen.conf --then $RESTART)
        (dropin ollama.service keep-alive.conf --then $RESTART)
        (dropin ollama.service hardening.conf --then $RESTART)
    ]
}
