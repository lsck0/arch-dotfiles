# the machine's facts: data, never code, so root reading them runs nothing

use log.nu *

const PLATFORM_LOCAL_DIR = "/etc/dotfiles"
const FORM_FACTORS = [desktop laptop vm wsl]
# the facts every module may read, exported to each module process as upper-case env names
export const PLATFORM_FACTS = [form_factor homelab wireguard secure_boot_own_keys lsck0_snapshot]
# the platform record's keys; anything else in a platform file is a typo, caught at load
const PLATFORM_KEYS = [hostname form_factor groups extra_packages facts packages_keep]

export def platform-groups-all [repo: path]: nothing -> list<string> {
    ls ($repo | path join configs) | where type == dir | get name | path basename | sort
}

export def platform-file [repo: path]: nothing -> any {
    let host = open --raw /etc/hostname | str trim
    [
        ($PLATFORM_LOCAL_DIR | path join platform.nuon)
        ($repo | path join platforms local.nuon)
        ($repo | path join platforms $"($host).nuon")
    ] | where ($it | path exists) | get --optional 0
}

export def platform-options-file [file: path]: nothing -> path {
    let parsed = $file | path parse
    $parsed.parent | path join $"($parsed.stem).options.nuon"
}

def platform-probe-form-factor []: nothing -> string {
    let virt = try { ^systemd-detect-virt | str trim } catch { "none" }
    if $virt == "wsl" {
        "wsl"
    } else if $virt != "none" {
        "vm"
    } else if (glob /sys/class/power_supply/BAT* | is-not-empty) {
        "laptop"
    } else {
        "desktop"
    }
}

export def platform-load [repo: path]: nothing -> record {
    let file = platform-file $repo
    let raw = if $file == null { {} } else { open $file }
    let unknown = $raw | columns | where $it not-in $PLATFORM_KEYS
    if ($unknown | is-not-empty) {
        error make {msg: $"($file): unknown keys ($unknown | str join ', '), known: ($PLATFORM_KEYS | str join ', ')"}
    }
    let all = platform-groups-all $repo
    let groups = $raw.groups? | default [] | if ($in | is-empty) { $all } else { $in }
    let bad = $groups | where $it not-in $all
    if ($bad | is-not-empty) {
        error make {msg: $"($file): groups has ($bad | str join ', '), not a group in configs/"}
    }
    let form_factor = $env.FORM_FACTOR? | default ($raw.form_factor? | default "")
        | if ($in | is-empty) { platform-probe-form-factor } else { $in }
    if $form_factor not-in $FORM_FACTORS {
        error make {msg: $"($file): form_factor '($form_factor)' is not one of ($FORM_FACTORS | str join ', ')"}
    }
    let facts = $raw.facts? | default {}
    let unknown_facts = $facts | columns | where $it not-in $PLATFORM_FACTS
    if ($unknown_facts | is-not-empty) {
        error make {msg: $"($file): unknown facts ($unknown_facts | str join ', '); a per-module setting is a module option"}
    }
    let options_file = if $file == null { null } else { platform-options-file $file }
    {
        file: $file
        hostname: ($raw.hostname? | default (open --raw /etc/hostname | str trim))
        form_factor: $form_factor
        groups: $groups
        extra_packages: ($raw.extra_packages? | default [])
        facts: ($PLATFORM_FACTS | reduce --fold {} {|name, acc| $acc | insert $name ($facts | get --optional $name) } | upsert form_factor $form_factor)
        packages_keep: ($raw.packages_keep? | default [])
        options_file: $options_file
        options: (if $options_file != null and ($options_file | path exists) { open $options_file } else { {} })
    }
}

export def platform-env [platform: record]: nothing -> record {
    $platform.facts | items {|name, value|
        let text = match ($value | describe) {
            "bool" => (if $value { "1" } else { "" })
            "nothing" => ""
            _ => ($value | into string)
        }
        {name: ($name | str uppercase), value: $text}
    } | transpose -r -d
}

export def platform-has [fact: string]: nothing -> bool {
    $env | get --optional ($fact | str uppercase) | default "" | is-not-empty
}

export def display-xwayland-scale [form_factor: string]: nothing -> int {
    if $form_factor == "laptop" { 1 } else { 2 }
}


const GPU_VENDORS = {"0x1002": amd, "0x8086": intel, "0x10de": nvidia}

# best first: most vram, then the one the firmware booted on
export def gpu-list []: nothing -> table {
    glob /sys/class/drm/card[0-9]* | where ($it | path basename) =~ '^card\d+$' | each {|card|
        let dev = $card | path join device
        let read = {|f| try { open --raw ($dev | path join $f) | str trim } catch { "" } }
        let pci = ^readlink -f $dev | path basename
        let render = ls ($dev | path join drm) | get name | path basename | where ($it | str starts-with renderD) | get --optional 0
        {
            index: ($card | path basename | str replace card "" | into int)
            vendor: ($GPU_VENDORS | get --optional (do $read vendor) | default other)
            vram: (do $read mem_info_vram_total | if ($in | is-empty) { 0 } else { into int } | into filesize)
            boot_vga: ((do $read boot_vga) == "1")
            render: (if $render == null { null } else { $"/dev/dri/($render)" })
            by_path: $"/dev/dri/by-path/pci-($pci)-render"
        }
    } | sort-by vram boot_vga --reverse
}
