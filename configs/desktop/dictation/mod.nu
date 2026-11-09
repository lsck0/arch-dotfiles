use module.nu *

# whisper-cpp and its pinned model come from programming/nvim (same dictation, into buffers); without them dictate.nu
# says so in a notification. No dep: desktop applies before programming.
export const meta = {packages: {pacman: [wtype]}}

export def link [cfg: record] {
    [(link-commands dictate.nu)]
}
