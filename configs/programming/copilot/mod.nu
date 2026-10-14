use module.nu *

export const meta = {packages: {pacman: [github-copilot-cli]}}

# no telemetry key: copilot cli only has the account's data-use toggles; gh's is GH_TELEMETRY in core/zsh
export def link [cfg: record] {
    json-merge ($nu.home-dir | path join .copilot settings.json) [(json-set [model] "claude-sonnet-5")]
}
