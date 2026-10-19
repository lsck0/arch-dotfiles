use module.nu *
export use ../boot/boot.nu [cmdline-set]
use ../boot/boot.nu [hooks-read hooks-write]

export const meta = {
    packages: {
        native: [
            alsa-firmware intel-media-driver jolt lib32-vulkan-radeon libinput-tools libva-utils linux-firmware
            linux-tools-meta lm_sensors sof-firmware vulkan-intel vulkan-nouveau vulkan-radeon wireless-regdb
        ]
    }
}

export const options = {
    nvidia_driver: {
        type: string?
        default: null
        doc: "NVIDIA driver branch: open (Turing on), 580xx (Maxwell to Volta), 470xx (Kepler), none (nouveau)"
        label: "NVIDIA driver"
        choices: [open 580xx 470xx none]
        scope: machine
    }
}

# pci device ids where each branch's chips begin: Turing (TU102), Maxwell (GM107), Kepler (GK104)
const NVIDIA_TURING = 0x1e00
const NVIDIA_MAXWELL = 0x1340
const NVIDIA_KEPLER = 0x0fc0
const NVIDIA_PACKAGES = {
    open: [nvidia-open-dkms nvidia-utils lib32-nvidia-utils]
    580xx: [nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils]
    470xx: [nvidia-470xx-dkms nvidia-470xx-utils lib32-nvidia-470xx-utils]
}

export def detect [cfg: record]: nothing -> record {
    let gpu = gpu-list | where vendor == nvidia | get --optional 0
    let id = if $gpu == null { 0 } else {
        open --raw $"/sys/class/drm/card($gpu.index)/device/device" | str trim | into int
    }
    let driver = match $id {
        _ if $id >= $NVIDIA_TURING => "open"
        _ if $id >= $NVIDIA_MAXWELL => "580xx"
        _ if $id >= $NVIDIA_KEPLER => "470xx"
        _ => "none"
    }
    {nvidia_driver: $driver}
}

export def packages [cfg: record]: nothing -> record {
    {native: ($NVIDIA_PACKAGES | get --optional ($cfg.nvidia_driver | default none) | default [])}
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" or $cfg.nvidia_driver == "none" { return [] }
    [(step cmdline-set nvidia_drm.modeset=1) (step kms-drop)]
}

# kms would put nouveau in the initramfs, which then claims the gpu before the nvidia modules load
export def kms-drop []: nothing -> nothing {
    hooks-write (hooks-read | where $it != kms)
}
