use module.nu *
export use ../boot/boot.nu [cmdline-set cmdline-unset]
use ../boot/boot.nu [hooks-read hooks-write hooks-insert]

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
    }
}

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
    if $env.FORM_FACTOR? == "wsl" { return [] }
    if ($cfg.nvidia_driver | default "none") == "none" {
        return [(step cmdline-unset nvidia_drm.modeset) (step kms-restore)]
    }
    [(step cmdline-set nvidia_drm.modeset=1) (step kms-drop)]
}

# Drops kms from the hooks: it would put nouveau in the initramfs, claiming the gpu before nvidia loads.
export def kms-drop []: nothing -> nothing {
    hooks-write (hooks-read | where $it != kms)
}

# Restores kms (inverse of kms-drop) so a box moved off nvidia gets early KMS back for plymouth.
export def kms-restore []: nothing -> nothing {
    let hooks = hooks-read
    if kms in $hooks { return }
    let anchor = [modconf udev base] | where $it in $hooks | get --optional 0
    if $anchor == null { error make {msg: "hardware: HOOKS has no modconf/udev/base to insert kms after"} }
    hooks-write (hooks-insert $hooks kms (($hooks | enumerate | where item == $anchor | get 0.index) + 1))
}
