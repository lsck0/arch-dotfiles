use module.nu *

# after claude: rtk init rewrites ~/.claude/settings.json whole, outside the engine's json lock
export const meta = {deps: [programming/claude], packages: {pacman: [rtk]}}

const CLAUDE_HOOK = "rtk hook claude"

export def link [cfg: record] {
    let claude_settings = $nu.home-dir | path join .claude settings.json
    let claude_hooked = try { open --raw $claude_settings | str contains $CLAUDE_HOOK } catch { false }
    [
        # --auto-patch: unattended, the patch prompts default to no and hooks never register
        (exec rtk-hermes [rtk init -g --auto-patch --agent hermes] --creates ($nu.home-dir | path join .hermes plugins rtk-rewrite))
        (exec rtk-copilot [rtk init -g --auto-patch --copilot] --creates ($nu.home-dir | path join .copilot hooks rtk-rewrite.json))
        (exec rtk-gemini [rtk init -g --auto-patch --gemini] --creates ($nu.home-dir | path join .gemini hooks rtk-hook-gemini.sh))
        (if $claude_hooked { [] } else { [(exec rtk-claude [rtk init -g --auto-patch --agent claude])] })
    ]
}
