use module.nu *

export const meta = {packages: {pacman: [uv]}}

export const options = {
    model: {
        type: string
        default: "RogerS-01/Josiefied-Qwen3-8B-abliterated-v1-AWQ"
        doc: "The hugging face repo vllm serves; an uncensored 4-bit AWQ build of Josiefied-Qwen3-8B-abliterated-v1"
        label: "Model"
        scope: machine
    }
    model_revision: {
        type: string
        default: 0244c2514cc272a603368c0440ff3002143b2336
        doc: "The model repo's commit, weights and tokenizer alike; bump from https://huggingface.co/api/models/<model>/revision/main"
        label: "Model revision"
        scope: machine
    }
    tool_call_parser: {
        type: string
        default: hermes
        doc: "vllm's tool call parser for the model's chat format (hermes for qwen3, gemma4 for gemma 4)"
        label: "Tool call parser"
        scope: machine
    }
    reasoning_parser: {
        type: string
        default: qwen3
        doc: "vllm's reasoning parser, which moves the model's thinking out of the reply into reasoning_content"
        label: "Reasoning parser"
        scope: machine
    }
    gpu_memory_utilization: {
        type: float?
        default: null
        doc: "The share of vram vllm takes; the rest stays for the desktop rendering on the same card"
        label: "GPU memory share"
        min: 0.1
        max: 0.95
        scope: machine
    }
}

const PREFIX = "/opt/vllm"
const VERSION = "0.30.0+rocm723"
const OMNI_VERSION = "0.30.0"
# the bare rocm/ index keeps only the newest release; rocm/<release>/<rocm tag>/ keeps the pin resolvable
const WHEELS_URL = "https://wheels.vllm.ai/rocm/0.30.0/rocm723/"
# rocm wheels are cp312 only
const PYTHON_VERSION = "3.12"
const ROCM_BIN = "/opt/rocm/bin"
const DESKTOP_VRAM = 4.5GiB
const SHARE_STEP = 0.05

export def detect [cfg: record]: nothing -> record {
    let gpu = gpu-list | where vendor == amd | get --optional 0
    if $gpu == null or $gpu.vram == 0b { return {gpu_memory_utilization: null} }
    let share = ($gpu.vram - $DESKTOP_VRAM) / $gpu.vram / $SHARE_STEP | math floor | $in * $SHARE_STEP
    {gpu_memory_utilization: ([([$share 0.1] | math max) 0.95] | math min | math round --precision 2)}
}

def rocm-gpu []: nothing -> bool {
    let info = try { ^($ROCM_BIN | path join rocminfo) | complete } catch { return false }
    $info.exit_code == 0 and ($info.stdout =~ '(?m)^Agent \d+') and ($info.stdout =~ 'gfx[0-9a-f]{3,}')
}

export def system [cfg: record] {
    if not (rocm-gpu) or $cfg.gpu_memory_utilization == null { return [] }
    let share = $cfg.gpu_memory_utilization | into string --decimals 2
    let values = {
        MODEL: $cfg.model, MODEL_REVISION: $cfg.model_revision, GPU_MEMORY_UTILIZATION: $share
        TOOL_CALL_PARSER: $cfg.tool_call_parser, REASONING_PARSER: $cfg.reasoning_parser
    }
    [
        (step venv)
        (file-copy vllm-wait-ready.nu /usr/local/bin/vllm-wait-ready --mode 755)
        (unit-file vllm-proxy.service)
        (file-render vllm.service (unit-dir | path join vllm.service) $values --then [
            systemctl try-restart vllm.service
        ])
        (unit-file vllm.socket --enable --now)
    ]
}

export def venv []: nothing -> nothing {
    mkdir $PREFIX
    if (^find $PREFIX ! -user root -print -quit | str trim | is-not-empty) { ^chown -R root:root $PREFIX }
    let venv = $PREFIX | path join venv
    with-env {UV_PYTHON_INSTALL_DIR: ($PREFIX | path join python)} {
        ^uv venv --allow-existing --python $PYTHON_VERSION $venv
        # mooncake's bundled glog clashes with the system's and aborts the import
        (^uv pip install --python $venv --extra-index-url $WHEELS_URL --excludes uv-excludes.txt $"vllm==($VERSION)"
            $"vllm-omni==($OMNI_VERSION)")
        ^uv pip uninstall --python $venv -r uv-excludes.txt
    }
    # torch's RUNPATH is $ORIGIN, so the libmpi_cxx stub goes beside it
    let platlib = ^($venv | path join bin python) -c 'import sysconfig; print(sysconfig.get_path("platlib"))' | str trim
    let build = mktemp --directory
    let stub = $build | path join libmpi_cxx.so.40
    ^cc -shared -fPIC -O2 -Wall -Werror -Wl,-soname,libmpi_cxx.so.40 -o $stub mpi-cxx-stub.c
    ^install -m755 $stub ($platlib | path join torch lib libmpi_cxx.so.40)
    rm --recursive $build
}
