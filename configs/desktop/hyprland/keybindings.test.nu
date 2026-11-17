#!/usr/bin/env -S nu --no-config-file
# Every target a bind in hyprland_keybindings.lua names exists: its scripts here and under $DOTFILES (executable), the
# ~/.local/bin commands some module links, the quickshell IPC target and function, the bar panels and the summoned
# plugin. A renamed script or IPC function otherwise leaves a key that silently does nothing.

const HERE = path self .
const REPO = path self ../../..
const QUICKSHELL = path self ../quickshell

def fail [msg: string] { error make {msg: $"keybindings.test: ($msg)"} }

def captures [text: string, pattern: string]: nothing -> list<string> {
    $text | parse --regex $pattern | get capture0 | uniq
}

def executable-check [file: path, what: string]: nothing -> nothing {
    if not ($file | path exists) { fail $"($what) ($file) does not exist" }
    if (^test -x $file | complete).exit_code != 0 { fail $"($what) ($file) is not executable" }
}

# quickshell's QML: target name to the text of the file declaring that IpcHandler.
def ipc-handlers []: nothing -> record {
    glob $"($QUICKSHELL)/**/*.qml" | each {|file|
        let text = open --raw $file
        # a plain `target: "x"`, or Bar.qml's per-screen `ownsGlobalIpcTarget ? "bar" : ...`
        let targets = (captures $text 'target:\s*"([^"]+)"') ++ (captures $text 'ipcTarget:[^\n]*\?\s*"([^"]+)"')
        $targets | each {|target| {target: $target, text: $text} }
    } | flatten | reduce --fold {} {|it, acc|
        $acc | upsert $it.target (($acc | get --optional $it.target | default "") + $it.text)
    }
}

def main [] {
    let lua = open --raw ($HERE | path join hyprland_keybindings.lua)

    for name in (captures $lua 'hypr_script\("([^"]+)"\)') {
        executable-check ($HERE | path join $name) "hypr_script"
    }
    for rel in (captures $lua '\$DOTFILES/([^ "'']+)' | where not ($it | str ends-with "/")) {
        executable-check ($REPO | path join $rel) "$DOTFILES script"
    }

    # scripts/mod.nu and the modules link <name>.nu or <name>.sh as ~/.local/bin/<name>
    let sources = glob $"($REPO)/{scripts,configs}/**/*.{nu,sh}" --exclude [**/secrets/**]
        | path parse | get stem | uniq
    for name in (captures $lua 'shell_bin\("([^"]+)"\)') {
        if $name not-in $sources { fail $"shell_bin ($name) has no ($name).nu or ($name).sh in the repo" }
    }

    let handlers = ipc-handlers
    let calls = (
        ($lua | parse --regex 'quickshell_call\("([^"]+)",\s*"([A-Za-z]+)' | rename target function)
        ++ ($lua | parse --regex 'quickshell_toggle\("([^"]+)"\)' | rename target | insert function toggle)
        ++ ($lua | parse --regex 'quickshell_cmd\("([^"]+)",\s*"([A-Za-z]+)"' | rename target function)
    )
    if ($calls | is-empty) { fail "found no quickshell calls; the parse is stale" }
    for call in $calls {
        let text = $handlers | get --optional $call.target
        if $text == null { fail $"quickshell IPC target ($call.target) is declared by no IpcHandler" }
        if not ($text =~ $"function ($call.function)\\\(") {
            fail $"quickshell IPC target ($call.target) has no function ($call.function)"
        }
    }

    let qml = glob $"($QUICKSHELL)/**/*.qml" | each { open --raw $in } | str join "\n"
    let panels = captures $lua 'panel = "([^"]+)"'
    if ($panels | is-empty) { fail "found no bar panels; the parse is stale" }
    for panel in $panels {
        if not ($qml =~ $"moduleName:\\s*\"($panel)\"") {
            fail $"bar panel ($panel) has no widget with that moduleName"
        }
    }

    let plugins = open --raw ($QUICKSHELL | path join plugins Plugins.js)
    for id in (captures $lua 'summon ([a-z.]+) ') {
        if not ($plugins =~ $"\"($id)\"") { fail $"summoned plugin ($id) is not in plugins/Plugins.js" }
    }
}
