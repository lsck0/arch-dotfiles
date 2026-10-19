#!/usr/bin/env -S nu --no-config-file
# close the editor on the project first: it rewrites project.godot on save

const PLUGIN = "res://addons/godot_mcp/plugin.cfg"
const RUNTIME = 'MCPRuntime="*res://addons/godot_mcp/runtime/mcp_runtime.gd"'
const ENABLED = "enabled=PackedStringArray("

def ini-add [lines: list<string>, section: string, line: string]: nothing -> list<string> {
    let header = $"[($section)]"
    let at = $lines | enumerate | where item == $header | get --optional 0.index
    if $at == null { return ($lines ++ ["" $header "" $line]) }
    let rest = $lines | skip ($at + 1)
    let rest = if ($rest | get --optional 0) == "" { $rest | skip 1 } else { $rest }
    ($lines | take ($at + 1)) ++ ["" $line] ++ $rest
}

# Put the godot mcp addon into a project and enable it.
def main [project: path = "."]: nothing -> nothing {
    let project = $project | path expand
    let conf = $project | path join project.godot
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    let addon = $data | path join godot-mcp addons godot_mcp
    if not ($conf | path exists) { print -e $"godot-mcp-addon: no project.godot in ($project)"; exit 1 }
    if not ($addon | path join plugin.cfg | path exists) {
        print -e $"godot-mcp-addon: no addon at ($addon) \(dot apply --user programming/godot\)"
        exit 1
    }
    mkdir ($project | path join addons)
    ^rsync -a --delete $"($addon)/" ($project | path join addons godot_mcp/)
    mut lines = open --raw $conf | lines
    if not ($lines | any { str contains $'"($PLUGIN)"' }) {
        let at = $lines | enumerate | where { $in.item | str starts-with $ENABLED } | get --optional 0.index
        $lines = if $at == null {
            ini-add $lines editor_plugins $'($ENABLED)"($PLUGIN)")'
        } else {
            let tail = $lines | get $at | str substring ($ENABLED | str length)..
            let sep = if ($tail | str starts-with ")") { "" } else { ", " }
            $lines | update $at $'($ENABLED)"($PLUGIN)"($sep)($tail)'
        }
    }
    if not ($lines | any { str starts-with "MCPRuntime=" }) { $lines = ini-add $lines autoload $RUNTIME }
    $lines | str join "\n" | $"($in)\n" | save --force $conf
    print $"godot-mcp-addon: enabled in ($project)"
}
