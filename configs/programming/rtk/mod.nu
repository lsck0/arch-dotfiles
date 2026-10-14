use module.nu *

export const meta = {packages: {pacman: [rtk]}}

const CLAUDE_HOOK = "rtk hook claude"

# unattended, the patch prompts default to no and hooks never register
export def link [cfg: record] {
    let claude_settings = $nu.home-dir | path join .claude settings.json
    let claude_hooked = try { open --raw $claude_settings | str contains $CLAUDE_HOOK } catch { false }
    [
        (exec rtk-hermes [rtk init -g --auto-patch --agent hermes] --creates ($nu.home-dir | path join .hermes plugins rtk-rewrite))
        (exec rtk-copilot [rtk init -g --auto-patch --copilot] --creates ($nu.home-dir | path join .copilot hooks rtk-rewrite.json))
        (exec rtk-gemini [rtk init -g --auto-patch --gemini] --creates ($nu.home-dir | path join .gemini hooks rtk-hook-gemini.sh))
        (if $claude_hooked { [] } else { [(exec rtk-claude [rtk init -g --auto-patch --agent claude])] })
    ]
}
