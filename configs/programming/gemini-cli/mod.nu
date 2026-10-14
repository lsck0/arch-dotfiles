use module.nu *

export const meta = {packages: {pacman: [gemini-cli]}}

export def link [cfg: record] {
    json-merge ($nu.home-dir | path join .gemini settings.json) [
        (json-set [usageStatisticsEnabled] false)
        (json-set [telemetry enabled] false)
    ]
}
