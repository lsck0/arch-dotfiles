use module.nu *

# serial, after claude: rtk init rewrites the agents' settings files whole, outside the engine's json lock, so it
# must not run beside a module merging into them (claude, gemini-cli, hermes, copilot)
export const meta = {deps: [programming/claude], packages: {pacman: [rtk]}, serial: true}

# the hook's entry in the settings file, not the hook script, tells a patch that never landed
def hooked [file: path, marker: string]: nothing -> bool {
    try { open --raw $file | str contains $marker } catch { false }
}

export def link [cfg: record] {
    let home = $nu.home-dir
    let claude = hooked ($home | path join .claude settings.json) "rtk hook claude"
    let gemini = hooked ($home | path join .gemini settings.json) "rtk-hook-gemini"
    [
        # --auto-patch: unattended, the patch prompts default to no and hooks never register
        (exec rtk-hermes [rtk init -g --auto-patch --agent hermes] --creates ($home | path join .hermes plugins rtk-rewrite))
        (exec rtk-copilot [rtk init -g --auto-patch --copilot] --creates ($home | path join .copilot hooks rtk-rewrite.json))
        (if $gemini { [] } else { [(exec rtk-gemini [rtk init -g --auto-patch --gemini])] })
        (if $claude { [] } else { [(exec rtk-claude [rtk init -g --auto-patch --agent claude])] })
    ]
}
