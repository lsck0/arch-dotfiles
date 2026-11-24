use module.nu *

export const meta = {packages: {pacman: [gamemode lib32-gamemode]}}

export const options = {
    gpu_device: {
        type: int?
        default: null
        doc: "The /dev/dri/cardN gamemode tunes while a game runs; none leaves the gpu alone"
        label: "GPU card"
    }
    amd_performance_level: {
        type: string?
        default: null
        doc: "The amdgpu power_dpm_force_performance_level during a game; high holds the clocks up, wasteful on battery"
        label: "AMD performance level"
        choices: [auto high]
    }
    renice: {
        type: int
        default: 10
        doc: "Niceness gamemode lowers a game by, gamemode.ini renice"
        label: "Renice"
        min: 0
        max: 20
    }
    pin_cores: {
        type: bool
        default: true
        doc: "Pin a game to the cores with the largest l3 (an x3d's v-cache ccd)"
        label: "Pin cores"
    }
}

export def detect [cfg: record]: nothing -> record {
    let gpu = gpu-list | get --optional 0
    {
        gpu_device: $gpu.index?
        amd_performance_level: (if $gpu.vendor? == "amd" and $env.FORM_FACTOR? == "desktop" { "high" } else { "auto" })
    }
}

# gamemoded reads [gpu] only from root-owned files (/etc, /usr/share): from ~/.config it drops every key with
# "not configurable from unsafe config files"
export def gpu-section [device: any, vendor: any, level: any]: nothing -> string {
    if $device == null { return "" }
    let amd = if $vendor == "amd" and $level != null { $"amd_performance_level=($level)\n" } else { "" }
    $"[gpu]\napply_gpu_optimisations=accept-responsibility\ngpu_device=($device)\n($amd)"
}

export def link [cfg: record] {
    [
        (file-render config/gamemode.ini (xdg config gamemode.ini) {
            RENICE: $cfg.renice, PIN_CORES: (if $cfg.pin_cores { "yes" } else { "no" })
        })
        (link-commands scripts/gamemode-hook.nu)
    ]
}

export def system [cfg: record] {
    let vendor = gpu-list | where index == $cfg.gpu_device | get --optional 0.vendor
    let gpu = gpu-section $cfg.gpu_device $vendor $cfg.amd_performance_level
    [
        (if $gpu != "" { file-text /etc/gamemode.ini $gpu })
        (file-copy scripts/split-lock-mitigate.nu /usr/local/bin/split-lock-mitigate --mode 755)
        (polkit-rules config/49-gamemode-services.rules)
        (group-admins gamemode)
    ]
}
