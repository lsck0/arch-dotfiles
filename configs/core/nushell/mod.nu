use module.nu *

export const meta = {packages: {pacman: [nushell]}, inputs: [/usr/bin/starship /usr/bin/zoxide]}

const INITS = {starship.nu: [starship init nu], zoxide.nu: [zoxide init nushell]}

export def link [cfg: record] {
    let vendor = xdg cache nushell
    [
        (files-into (xdg config nushell) env.nu config.nu)
        ($INITS | items {|file, argv|
            if (which $argv.0 | is-empty) { [] } else { file-text ($vendor | path join $file) $"(^$argv.0 ...($argv | skip 1))\n" --generated }
        } | decls-flatten)
    ]
}
