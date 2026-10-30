use module.nu *

export const meta = {packages: {pacman: [ollama]}}

const RESTART = [systemctl try-restart ollama.service]
export const KEEP_ALIVE_MIN = 30

export def link [cfg: record] {
    link-commands ollama-ensure-models.nu
}

export def system [cfg: record] {
    [
        (unit-file ollama-proxy.service)
        (unit-file ollama.socket --enable --now)
        (dropin ollama.service listen.conf --then $RESTART)
        (file-render keep-alive.conf (unit-dir | path join ollama.service.d keep-alive.conf)
            {KEEP_ALIVE_MIN: $KEEP_ALIVE_MIN} --then $RESTART)
        (dropin ollama.service hardening.conf --then $RESTART)
        (dropin ollama.service gpu.conf --then $RESTART)
        (dropin ollama.service perf.conf --then $RESTART)
    ]
}
