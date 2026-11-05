use module.nu *

export const meta = {deps: [base/essentials], packages: {pacman: [uv]}}

const COMFYUI_URL = "https://github.com/comfyanonymous/ComfyUI"
# v0.43.0; pyproject.toml carries this tag's requirements.txt, bump both together
const COMFYUI_COMMIT = "426f5eea52a7ece1dd599fff4cb6cd1f352ddd24"
# the torch rocm wheels hold one model at a time beside the desktop on a 16 GB card; smaller cards stay without
const VRAM_MIN = 12GiB
const HF = "https://huggingface.co"
# each file pinned by repo commit and its lfs sha256 (https://huggingface.co/api/models/<repo>/tree/<commit>); placed
# where the bundled workflow templates look for it (Templates, "Flux Schnell" and "Hunyuan3D 2.1")
export const MODELS = [
    # text to image, Apache-2.0; the fp8 single-file checkpoint carries clip, t5 and the vae
    {repo: "Comfy-Org/Flux-1-Schnell", commit: d31e04067066d92c55ece2b01748dcc337725d7a, file: flux1-schnell-fp8.safetensors
        dir: checkpoints, sha256: ead426278b49030e9da5df862994f25ce94ab2ee4df38b556ddddb3db093bf72}
    # image to 3d mesh (glb); tencent-hunyuan-community license, which excludes the EU, UK and South Korea
    {repo: "Comfy-Org/Hunyuan-3D-2.1", commit: d28dcff0eb85a3740955e24cb1d53def66591278, file: hunyuan_3d_v2.1.safetensors
        dir: checkpoints, sha256: 5f21e98a6cb99b13b5e224abaee33929570fff7af2b6a0060001559a04ba9d72}
]
const MODELS_TIMEOUT = 3hr

def root []: nothing -> path { xdg data comfyui }

def gpu-fits []: nothing -> bool {
    gpu-list | any {|g| $g.vendor == amd and $g.vram >= $VRAM_MIN }
}

export def link [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" or not (gpu-fits) { return [] }
    let root = root
    let src = $root | path join src
    let values = {
        PYTHON: ($root | path join venv bin python), SRC: $src, BASE: $root
        OUTPUT: ($nu.home-dir | path join pictures comfyui), WAIT_READY: ($root | path join comfyui-wait-ready.nu)
    }
    [
        (fetch-git $COMFYUI_URL $COMFYUI_COMMIT $src)
        (step venv --network --timeout 60min --requires ($src | path join main.py))
        (step models --network --timeout $MODELS_TIMEOUT)
        (file-copy comfyui-wait-ready.nu $values.WAIT_READY --mode 755)
        (file-render comfyui.service (unit-dir | path join comfyui.service) $values --then [
            # try-restart: a restart would start it outside the socket, holding vram with no idle exit
            systemctl --user try-restart comfyui.service
        ])
        (file-render comfyui-proxy.service (unit-dir | path join comfyui-proxy.service) $values)
        (unit-file comfyui.socket --enable --now)
    ]
}

# Everything the venv is built from; a venv whose stamp matches is left alone.
def venv-stamp []: nothing -> string {
    [$COMFYUI_COMMIT (open --raw pyproject.toml | hash sha256) (open --raw uv.lock | hash sha256)] | str join "\n" | $"($in)\n"
}

# The venv from uv.lock, exactly: --locked refuses a lock out of date with pyproject.toml, --exact drops strays.
export def venv []: nothing -> nothing {
    let root = root
    let stamp_path = $root | path join venv.stamp
    let stamp = venv-stamp
    if ($root | path join venv bin python | path exists) and ($stamp_path | path exists) and (open --raw $stamp_path) == $stamp { return }
    with-env {UV_PROJECT_ENVIRONMENT: ($root | path join venv), UV_PYTHON_INSTALL_DIR: ($root | path join python)} {
        ^uv sync --locked --exact --no-install-project --project $env.PWD
    }
    $stamp | save --force $stamp_path
}

# Each pinned model once: curl resumes a partial .part, and only a file matching its sha256 takes the real name.
export def models []: nothing -> nothing {
    let dir = root | path join models
    let stamps = $dir | path join .pins
    mkdir $stamps
    for m in $MODELS {
        let dest = $dir | path join $m.dir $m.file
        let stamp = $stamps | path join $m.sha256
        if ($dest | path exists) and ($stamp | path exists) { continue }
        # a file in place without its stamp (a wiped .pins) is hashed once instead of fetched again
        if ($dest | path exists) and (^sha256sum $dest | split row " " | first) == $m.sha256 { touch $stamp; continue }
        mkdir ($dest | path dirname)
        # named by the pin, so a partial download of an earlier pin is never resumed into this one
        let part = $"($dest).($m.sha256).part"
        let url = $"($HF)/($m.repo)/resolve/($m.commit)/($m.file)"
        ^curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -C - -o $part $url
        let got = ^sha256sum $part | split row " " | first
        if $got != $m.sha256 {
            rm --force $part
            error make {msg: $"comfyui: ($url) is ($got), pinned ($m.sha256); removed"}
        }
        mv --force $part $dest
        touch $stamp
    }
}
