use module.nu *
use scripts/ollama-ensure-models.nu [SMALL LARGE EMBEDDING CODING LONG_CONTEXT LONG_CONTEXT_TOKENS]

export const meta = {packages: {pacman: [ollama]}}

# the socket starts both again on the next request, with the new settings; a restart of ollama alone stops the proxy
# bound to it, and that stop cancels ollama's start job
const RESTART = [systemctl stop ollama-proxy.service ollama.service]
# kept free when no gpu reports its vram
const GPU_OVERHEAD_FALLBACK = 512MiB
# the pinned set is pulled only beside a gpu this large: an apu's carveout reports a few hundred MB of vram
const VRAM_MIN = 8GiB

export const options = {
    vram_percent: {
        type: int
        default: 80
        doc: "Share of the largest gpu's vram ollama may fill; the rest stays free for the desktop, and a model that does not fit runs partly on the cpu"
        label: "VRAM share (%)"
    }
    parallel: {
        type: int
        default: 4
        doc: "Requests one loaded model answers at once; each slot holds its own context in vram"
        label: "Parallel requests"
    }
    keep_alive_min: {
        type: int
        default: 30
        doc: "Idle minutes before a loaded model is unloaded and ollama stops"
        label: "Keep alive (min)"
        min: 1
        max: 1440
    }
    pull_models: {
        type: bool
        default: true
        doc: "Pull the pinned models (tens of GB) where a gpu has the vram for them; off leaves the store to ollama pull"
        label: "Pull pinned models"
    }
    prune_unpinned: {
        type: bool
        default: true
        doc: "Remove every model the pins do not keep after a pull, those pulled by hand included"
        label: "Remove unpinned models"
    }
}
# the pinned models are tens of GB: pulled once per pin set, and only where a gpu runs them (not the vm test)
const MODELS_TIMEOUT = 6hr

export def link [cfg: record] {
    # the script's own hash too: a changed prune or ensure rule reruns it without a pin bump
    let script = open --raw scripts/ollama-ensure-models.nu | hash sha256
    let keep = if $cfg.prune_unpinned { [] } else { [--keep-unpinned] }
    let pins = [$SMALL.pin $LARGE.pin $EMBEDDING.pin $CODING.pin $LONG_CONTEXT $LONG_CONTEXT_TOKENS $script ...$keep]
        | str join "\n" | hash sha256 | str substring 0..<12
    let gpus = gpu-list
    # arch's ollama is the cpu build; rocm/compute adds the amd backend, nothing here the nvidia one (ollama-cuda)
    if ($gpus | any { $in.vendor == nvidia }) and (glob /usr/lib/ollama/cuda_*/libggml-cuda.so | is-empty) {
        log-note "llm/ollama: runs on the cpu; ollama-cuda in the platform's extra_packages adds the nvidia gpu"
    }
    [
        (link-commands scripts/ollama-ensure-models.nu)
        (if $cfg.pull_models and ($gpus | any { $in.vram >= $VRAM_MIN }) {
            (exec ollama-models [nu --no-config-file ($env.PWD | path join scripts ollama-ensure-models.nu) ...$keep]
                --key $pins --network --timeout $MODELS_TIMEOUT)
        })
    ]
}

export def system [cfg: record] {
    [
        (unit-file services/ollama-proxy.service --values {KEEP_ALIVE_MIN: $cfg.keep_alive_min})
        (unit-file services/ollama.socket --enable --now)
        ([services/listen.conf services/hardening.conf services/gpu.conf] | each { dropin ollama.service $in --then $RESTART })
        (dropin ollama.service services/perf.conf --values {GPU_OVERHEAD: (gpu-overhead $cfg), PARALLEL: $cfg.parallel}
            --then $RESTART)
        (dropin ollama.service services/keep-alive.conf --values {KEEP_ALIVE_MIN: $cfg.keep_alive_min} --then $RESTART)
    ]
}

# Bytes ollama leaves free: what vram_percent leaves of the largest gpu.
def gpu-overhead [cfg: record]: nothing -> int {
    let vram = gpu-list | get vram | append 0b | math max
    let free = if $vram == 0b { $GPU_OVERHEAD_FALLBACK } else { $vram * (100 - $cfg.vram_percent) / 100 }
    $free | into int
}
