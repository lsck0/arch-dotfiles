use module.nu *

export const meta = {packages: {pacman: [telegram-desktop]}}

# a stable import path for the wallust-rendered palette; telegram cannot load or reload one by itself (README)
export def link [cfg: record] {
    let palette = $nu.home-dir | path join .cache wal colors-telegram.tdesktop-palette
    file-link $palette ($nu.home-dir | path join .local share TelegramDesktop pywal-cyberpunk.tdesktop-palette)
}
