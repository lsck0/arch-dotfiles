#!/usr/bin/env -S nu --no-config-file

const SCRIPT_RELATIVE = "configs/programming/trmnl-claude/scripts/trmnl-claude.nu"
const TIMEOUT = "60s"
const TIMEOUT_EXIT_CODE = 124
# agent_usage_limits in mod.nu, through prefs.json: off, the script skips the rate-limit request on the Claude plan
const PREFS = ($nu.home-dir | path join .config quickshell prefs.json)

def main [] {
    let repo = $env.DOTFILES? | default ($nu.home-dir | path join projects arch-dotfiles)
    let script = $repo | path join $SCRIPT_RELATIVE
    let claude = [($nu.home-dir | path join .claude) ($nu.home-dir | path join .config claude)] | any { path exists }
    if not $claude or not ($script | path exists) {
        print "{}"
        return
    }
    let limits = (try { open $PREFS | get --optional agentLimits } catch { null }) != false
    let done = ^timeout $TIMEOUT $script --dry-run ...(if $limits { [] } else { [--no-scrape] }) | complete
    let reply = if $done.exit_code == $TIMEOUT_EXIT_CODE {
        {error: "timeout"}
    } else if $done.exit_code != 0 {
        {error: $"exit ($done.exit_code)"}
    } else {
        try { $done.stdout | from json | default {error: "bad json"} } catch { {error: "bad json"} }
    }
    print ($reply | to json -r)
}
