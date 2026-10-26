use module.nu *

export const meta = {packages: {pacman: [telegram-desktop]}}

export def link [cfg: record] {
    let palette = xdg cache wal colors-telegram.tdesktop-palette
    file-link $palette (xdg data TelegramDesktop pywal-cyberpunk.tdesktop-palette)
}
