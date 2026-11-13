use module.nu *
use ollama-ensure-models.nu [SMALL LARGE EMBEDDING CODING LONG_CONTEXT LONG_CONTEXT_TOKENS]

export const meta = {packages: {pacman: [ollama]}}

# the socket starts both again on the next request, with the new settings; a restart of ollama alone stops the proxy
# bound to it, and that stop cancels ollama's start job
const RESTART = [systemctl stop ollama-proxy.service ollama.service]
export const KEEP_ALIVE_MIN = 30
# kept free when no gpu reports its vram
const GPU_OVERHEAD_FALLBACK = 512MiB

export const options = {
    vram_percent: {
        type: int
        default: 80
        doc: "Share of the largest gpu's vram ollama may fill; the rest stays free for the desktop, and a model that does not fit runs partly on the cpu"
        label: "VRAM share (%)"
    }
}
# the pinned models are tens of GB: pulled once per pin set, and only where a gpu runs them (not the vm test)
const MODELS_TIMEOUT = 6hr

export def link [cfg: record] {
    # the script's own hash too: a changed prune or ensure rule reruns it without a pin bump
    let script = open --raw ollama-ensure-models.nu | hash sha256
    let pins = [$SMALL.pin $LARGE.pin $EMBEDDING.pin $CODING.pin $LONG_CONTEXT $LONG_CONTEXT_TOKENS $script] | str join "\n"
        | hash sha256 | str substring 0..<12
    [
        (link-commands ollama-ensure-models.nu)
        (if (gpu-list | where vram > 0b | is-not-empty) {
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
        ([listen.conf hardening.conf gpu.conf] | each { dropin ollama.service $in --then $RESTART })
        (file-render perf.conf (unit-dir | path join ollama.service.d perf.conf) {GPU_OVERHEAD: (gpu-overhead $cfg)}
            --then $RESTART)
        (file-render keep-alive.conf (unit-dir | path join ollama.service.d keep-alive.conf)
            {KEEP_ALIVE_MIN: $KEEP_ALIVE_MIN} --then $RESTART)
    ]
}

# Bytes ollama leaves free: what vram_percent leaves of the largest gpu.
def gpu-overhead [cfg: record]: nothing -> int {
    let vram = gpu-list | get vram | append 0b | math max
    let free = if $vram == 0b { $GPU_OVERHEAD_FALLBACK } else { $vram * (100 - $cfg.vram_percent) / 100 }
    $free | into int
}
