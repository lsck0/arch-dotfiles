use module.nu *

export const meta = {packages: {pacman: [ollama-rocm python-pytorch-opt-rocm]}, inputs: [/etc/group]}

# interactive ROCm/HIP (pytorch, blender HIP, llama.cpp-hip) reaches /dev/kfd and /dev/dri through these groups;
# without an AMD GPU (or on wsl) there is nothing to reach
export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" or not (gpu-list | any { $in.vendor == "amd" }) { return [] }
    [(group-admins render) (group-admins video)]
}
