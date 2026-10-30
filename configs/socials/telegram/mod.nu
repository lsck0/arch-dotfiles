use module.nu *

export const meta = {deps: [core/wallust], packages: {pacman: [telegram-desktop]}}

const PALETTE_RENDERED = "colors-telegram.tdesktop-palette"
# a stable path in Telegram's own data dir for the manual import in README.md
const PALETTE_IMPORT = "wallust.tdesktop-palette"

export def link [cfg: record] { [] }

export def theme [cfg: record, wallpaper: string] {
    let rendered = xdg cache wal $PALETTE_RENDERED
    if not ($rendered | path exists) { return [] }
    file-text (xdg data TelegramDesktop $PALETTE_IMPORT) (open --raw $rendered) --generated
}
