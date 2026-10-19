use module.nu *

export const meta = {packages: {pacman: [github-copilot-cli]}}

export def link [cfg: record] {
    json-merge ($nu.home-dir | path join .copilot settings.json) [(json-set [model] "claude-sonnet-5")]
}
