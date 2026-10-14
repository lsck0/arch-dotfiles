#!/usr/bin/env -S nu --no-config-file
# claude code usage for the bar: the payload, {} where the widget does not apply, or {"error": why}

const USAGE_USER = "luca"
const SCRIPT_RELATIVE = "configs/programming/trmnl-claude/trmnl-claude.nu"
const TIMEOUT = "60s"
const TIMEOUT_EXIT_CODE = 124

def main [] {
    let repo = $env.DOTFILES? | default ($env.FILE_PWD | path join ../../../../../.. | path expand)
    let script = $repo | path join $SCRIPT_RELATIVE
    if $env.USER != $USAGE_USER or not ($script | path exists) {
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
