use module.nu *

export const meta = {packages: {pacman: [lib32-vkbasalt vkbasalt]}}

export const options = {
    sharpness: {
        type: float
        default: 0.4
        doc: "Contrast adaptive sharpening strength, vkBasalt.conf casSharpness"
        label: "Sharpness"
        min: 0.0
        max: 1.0
        step: 0.05
        scope: user
    }
    enable_on_launch: {
        type: bool
        default: true
        doc: "Effects on from a game's start; Home toggles them"
        label: "On at launch"
        scope: user
    }
}

export def link [cfg: record] {
    file-render config/vkBasalt.conf (xdg config vkBasalt vkBasalt.conf) {
        SHARPNESS: $cfg.sharpness, ENABLE_ON_LAUNCH: (if $cfg.enable_on_launch { "True" } else { "False" })
    }
}
