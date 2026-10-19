use module.nu *

export const meta = {packages: {pacman: [konsole]}}

const DATA_DIR = ".local/share/konsole"

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $DATA_DIR
    [
        (file-copy pywal.profile ($dir | path join pywal.profile))
        (file-link ($nu.home-dir | path join .cache wal colors-konsole.colorscheme) ($dir | path join pywal.colorscheme))
        # konsole rewrites konsolerc with window state, so only the key is set
        (exec konsole-profile [kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile pywal.profile])
    ]
}
