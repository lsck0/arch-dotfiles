#!/usr/bin/env -S nu --no-config-file
# The pass-through launchers hand a command line on: every argument must arrive as typed, with nothing in it evaluated
# on the way (a nu `def --wrapped main` runs a --flag=(expr) value and requotes others). What each one execs is a stub
# printing its arguments; one named by an absolute path is swapped for the stub in a copy of the launcher.

use std/assert

const REPO = path self ..
const PRINT = "#!/bin/sh\nprintf '%s\\n' \"$@\"\n"
const STUBS = {
    sudo: $PRINT, systemd-run: $PRINT, choom: $PRINT, blender: $PRINT, kitty: $PRINT, target: $PRINT
    id: "#!/bin/sh\ncase \"$1\" in -gn) echo \"${STUB_GROUP:-users}\" ;; -nG) echo \"users wheel\" ;; esac\n"
    # portmaster up for pentest, no user manager for fence, no ghostty answering for ghostty-window
    systemctl: "#!/bin/sh\n[ \"$1\" = is-active ]\n"
    timeout: "#!/bin/sh\n[ \"${STUB_GHOSTTY:-}\" = up ]\n"
}
const COMMAND = "/usr/bin/printf"
const COMMAND_FORMAT = '%s\n'

# Arguments nothing may evaluate or requote; the root helpers' tests share them, and each one naming marker creates it
# when evaluated.
export def hostile [marker: path]: nothing -> list<string> {
    [
        $"--x=\(touch ($marker)\)" $"--x=$\(touch ($marker)\)" $"--x=a\(touch ($marker)\)" $"--x \(touch ($marker)\)"
        $"--help=\(touch ($marker)\)" $"--help \(touch ($marker)\)" $"-x=\(touch ($marker)\)" $"\(touch ($marker)\)"
        $"$\(touch ($marker)\)" $"a; touch ($marker)" $"`touch ($marker)`"
        "--name=$env.HOME" "--user=$HOME" "-s" "--data={\"k\": [1, 2]}" "--title two" "two words" "*" "true" "--"
    ]
}

# The launcher as it is, or a copy with each absolute target in swap pointing at the stub.
def launcher [file: path, swap: list<string>, work: path]: nothing -> path {
    let source = $REPO | path join $file
    if ($swap | is-empty) { return $source }
    let copy = $work | path join ($file | path basename)
    $swap | reduce --fold (open --raw $source) {|target, text|
        assert str contains $text $target $"($file) no longer names ($target)"
        $text | str replace --all $target ($work | path join bin target)
    } | save --force $copy
    chmod +x $copy
    $copy
}

# The output must end with tail: what a launcher puts before the command (a cpu pin, a unit name) varies by machine.
def passed-check [what: string, run: record, tail: list<string>, marker: path]: nothing -> nothing {
    assert (not ($marker | path exists)) $"($what) evaluated an argument"
    assert equal $run.exit_code 0 $"($what) exited ($run.exit_code): ($run.stderr | str trim)"
    assert equal ($run.stdout | lines | last ($tail | length)) $tail $"($what) passed the wrong argv tail"
}

def main [] {
    let work = mktemp --directory
    let marker = $work | path join evaluated
    let bin = $work | path join bin
    mkdir $bin
    for stub in ($STUBS | transpose name text) {
        $stub.text | save ($bin | path join $stub.name)
        chmod +x ($bin | path join $stub.name)
    }
    let args = hostile $marker
    let command = [$COMMAND $COMMAND_FORMAT]
    let start = $REPO | path join configs creating blender mcp-start.py
    let cases = [
        [file swap given tail env];
        [configs/core/yt-dlp/yt-dlp.sh [/usr/local/bin/yt-dlp] $args $args {}]
        [configs/base/v4l-utils/qvidcap.sh [/usr/bin/qvidcap] $args $args {}]
        [configs/pentesting/zaproxy/zaproxy-launch.sh [/usr/share/zaproxy/zap.sh] $args ([-silent -configfile ($work | path join .ZAP mcp.properties)] ++ $args) {}]
        [configs/creating/blender/blender-mcp-bridge.sh [] $args ($args ++ [--python $start]) {}]
        [configs/core/zsh/fence.sh [] ($command ++ $args) ([nice -n19] ++ $command ++ $args) {}]
        [configs/base/sandbox/confine.sh [] ([--] ++ $command ++ $args) ([--] ++ $command ++ $args) {}]
        [configs/base/sandbox/sandbox-build.sh [] ([-w $work --] ++ $command ++ $args) ([--] ++ $command ++ $args) {}]
        [configs/base/sandbox/sandbox-build.sh [] ([$"--work=($work)"] ++ $command ++ $args) ([--] ++ $command ++ $args) {}]
        [configs/pentesting/pentest/pentest.sh [] ($command ++ $args) ([-g pentest -- /usr/bin/env $"PATH=($bin):/usr/bin"] ++ $command ++ $args) {}]
        [configs/pentesting/pentest/pentest.sh [] ($command ++ $args) $args {STUB_GROUP: pentest}]
        [configs/desktop/ghostty/xdg/ghostty-window.sh [/usr/bin/ghostty] $args ([+new-window] ++ $args) {STUB_GHOSTTY: up}]
        [configs/desktop/ghostty/xdg/ghostty-window.sh [] $args $args {}]
        [configs/desktop/ghostty/xdg/ghostty-window.sh [] (["--title=two words" "--working-directory=/a b" -e] ++ $command ++ ["--title=kept" -e]) ([--title "two words" --directory "/a b"] ++ $command ++ ["--title=kept" -e]) {}]
    ]
    mkdir ($work | path join .ZAP)
    touch ($work | path join .ZAP mcp.properties)
    try {
        for case in $cases {
            let run = with-env ({PATH: $"($bin):/usr/bin", HOME: $work} | merge $case.env) {
                ^(launcher $case.file $case.swap $work) ...$case.given | complete
            }
            passed-check $"($case.file) ($case.env | to nuon)" $run $case.tail $marker
        }
    } catch {|err|
        rm --recursive --force $work
        error make {msg: $err.msg}
    }
    rm --recursive --force $work
}
