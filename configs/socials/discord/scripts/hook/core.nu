# The host's modules dir and its newest discord_desktop_core dir, the one both hooks act on, null without a host. The
# core is null until the host has downloaded its modules.

use ../../../../../scripts/lib/state.nu [xdg]

export def desktop-core []: nothing -> any {
    let host = xdg config discord Discord
    if not ($host | path exists) { return null }
    let modules = $host | path expand | path dirname | path join modules
    let core = glob ($modules | path join discord_desktop_core-*) | sort --natural | last 1 | get --optional 0
    {modules: $modules, core: $core}
}
