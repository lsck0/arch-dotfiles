use module.nu *

# the rocm builds of llm/ollama and heretic-llm (llm/tools) live here: the rocm group marks an amd gpu, the vm runs llm
# without it on the cpu builds
export const meta = {packages: {pacman: [ollama-rocm python-pytorch-opt-rocm]}, inputs: [/etc/group]}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" or not (gpu-list | any { $in.vendor == "amd" }) { return [] }
    [(group-admins render) (group-admins video)]
}
