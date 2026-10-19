use module.nu *

export const meta = {packages: {pacman: [ollama-rocm python-pytorch-opt-rocm]}, inputs: [/etc/group]}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" or not (gpu-list | any { $in.vendor == "amd" }) { return [] }
    [(group-admins render) (group-admins video)]
}
