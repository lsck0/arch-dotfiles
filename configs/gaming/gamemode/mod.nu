use module.nu *

export const meta = {packages: {pacman: [gamemode lib32-gamemode]}}

export const options = {
    gpu_device: {
        type: int?
        default: null
        doc: "The /dev/dri/cardN gamemode tunes while a game runs; none leaves the gpu alone"
        label: "GPU card"
        scope: machine
    }
    amd_performance_level: {
        type: string?
        default: null
        doc: "The amdgpu power_dpm_force_performance_level during a game; high holds the clocks up, wasteful on battery"
        label: "AMD performance level"
        choices: [auto high]
        scope: machine
    }
}

export def detect [cfg: record]: nothing -> record {
    let gpu = gpu-list | get --optional 0
    {
        gpu_device: $gpu.index?
        amd_performance_level: (if $gpu.vendor? == "amd" and $env.FORM_FACTOR? == "desktop" { "high" } else { "auto" })
    }
}

export def link [cfg: record] {
    let gpu = if $cfg.gpu_device == null { "" } else {
        let level = if (gpu-list | where index == $cfg.gpu_device | get --optional 0.vendor) == "amd" {
            $"amd_performance_level=($cfg.amd_performance_level)\n"
        } else { "" }
        $"\n[gpu]\napply_gpu_optimisations=accept-responsibility\ngpu_device=($cfg.gpu_device)\n($level)"
    }
    [
        (file-text ($nu.home-dir | path join .config gamemode.ini) $"(open --raw gamemode.ini)($gpu)")
        (link-commands gamemode-hook.nu)
    ]
}

export def system [cfg: record] {
    [
        (file-copy split-lock-mitigate.nu /usr/local/bin/split-lock-mitigate --mode 755)
        (file-copy 49-gamemode-services.rules /etc/polkit-1/rules.d/49-gamemode-services.rules)
        (group-admins gamemode)
    ]
}
