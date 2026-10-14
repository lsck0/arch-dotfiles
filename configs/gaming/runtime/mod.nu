# what games run on beside steam's own runtime: cachyos proton, d3d12 for system wine, gamescope, the vulkan tooling
export const meta = {
    packages: {
        pacman: [
            gamescope glslang lib32-vkd3d proton-cachyos-slr protontricks shaderc spirv-tools vkd3d vulkan-tools
            vulkan-validation-layers
        ]
    }
}
