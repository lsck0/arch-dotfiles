use module.nu *

export const meta = {packages: {pacman: [nushell]}, inputs: [/usr/bin/starship /usr/bin/zoxide], reads: [core/fastfetch]}

export const options = {
    edit_mode: {
        type: string
        default: emacs
        doc: "Line editor keymap"
        label: "Edit mode"
        choices: [emacs vi]
        scope: user
    }
    history_size: {
        type: int
        default: 100000
        doc: "Commands the history keeps"
        label: "History size"
        min: 0
        scope: user
    }
}

const INITS = {starship.nu: [starship init nu], zoxide.nu: [zoxide init nushell]}

# nu's own spelling of a large int, as config.nu writes it: 100_000
def int-grouped [n: int]: nothing -> string {
    $n | into string | str replace --all --regex '(\d)(?=(\d{3})+$)' '${1}_'
}

export def link [cfg: record] {
    let vendor = xdg cache nushell
    [
        (files-into (xdg config nushell) config/env.nu)
        (file-render config/config.nu (xdg config nushell config.nu) {
            EDIT_MODE: $cfg.edit_mode, HISTORY_SIZE: (int-grouped $cfg.history_size)
            # core/fastfetch's on_shell_start: off, the fetch looks for a command named "", which never exists
            FASTFETCH: (if $cfg.deps."core/fastfetch".on_shell_start { "fastfetch" } else { '""' })
        })
        ($INITS | items {|file, argv|
            if (which $argv.0 | is-not-empty) { file-text ($vendor | path join $file) $"(^$argv.0 ...($argv | skip 1))\n" --generated }
        })
    ]
}
