use module.nu *
use ollama-ensure-models.nu [SMALL LARGE EMBEDDING CODING LONG_CONTEXT LONG_CONTEXT_TOKENS]

export const meta = {packages: {pacman: [ollama]}}

# the socket starts both again on the next request, with the new settings; a restart of ollama alone stops the proxy
# bound to it, and that stop cancels ollama's start job
const RESTART = [systemctl stop ollama-proxy.service ollama.service]
export const KEEP_ALIVE_MIN = 30
# the pinned models are tens of GB: pulled once per pin set, and only where a gpu runs them (not the vm test)
const MODELS_TIMEOUT = 3hr

export def link [cfg: record] {
    # the script's own hash too: a changed prune or ensure rule reruns it without a pin bump
    let script = open --raw ($env.PWD | path join ollama-ensure-models.nu) | hash sha256
    let pins = [$SMALL.pin $LARGE.pin $EMBEDDING.pin $CODING.pin $LONG_CONTEXT $LONG_CONTEXT_TOKENS $script] | str join "\n"
        | hash sha256 | str substring 0..<12
    [
        (link-commands ollama-ensure-models.nu)
        (if (gpu-list | where vram > 0b | is-empty) { [] } else {
            # --done: the stamp it touched under $XDG_STATE_HOME/ollama-models before it was keyed
            (exec ollama-models [nu --no-config-file ($env.PWD | path join ollama-ensure-models.nu)] --key $pins
                --done=(xdg state ollama-models $pins | path exists) --network --timeout $MODELS_TIMEOUT)
        })
    ]
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
