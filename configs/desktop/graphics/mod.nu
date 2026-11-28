# The gpu's userspace for every vendor a machine may have (mesa, vulkan, va-api, opencl), and the libraries prebuilt
# gui binaries (AppImages, electron and game builds) load without declaring them. A machine without a desktop needs
# none of it.
export const meta = {
    packages: {
        pacman: [
            freetype2 libjpeg-turbo libpng libva libvips libxcomposite libxinerama mesa openal opencl-icd-loader
            vulkan-icd-loader
        ]
        native: [intel-media-driver libva-utils vulkan-intel vulkan-nouveau vulkan-radeon]
    }
}
