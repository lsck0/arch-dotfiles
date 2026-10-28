#!/usr/bin/env -S nu --no-config-file

const SCRIPT_RELATIVE = "configs/programming/trmnl-claude/trmnl-claude.nu"
const TIMEOUT = "60s"
const TIMEOUT_EXIT_CODE = 124

def main [] {
    let repo = $env.DOTFILES? | default ($nu.home-dir | path join projects arch-dotfiles)
    let script = $repo | path join $SCRIPT_RELATIVE
    let claude = [($nu.home-dir | path join .claude) ($nu.home-dir | path join .config claude)] | any { path exists }
    if not $claude or not ($script | path exists) {
        print "{}"
        return
    }
    let done = ^timeout $TIMEOUT $script --dry-run | complete
    let reply = if $done.exit_code == $TIMEOUT_EXIT_CODE {
        {error: "timeout"}
    } else if $done.exit_code != 0 {
        {error: $"exit ($done.exit_code)"}
    } else {
        try { $done.stdout | from json | default {error: "bad json"} } catch { {error: "bad json"} }
    }
    print ($reply | to json -r)
}
