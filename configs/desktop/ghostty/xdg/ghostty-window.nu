#!/usr/bin/env -S nu --no-config-file
# ghostty-window [--title=<title>] [--working-directory=<dir>] [-e <command...>]: what xdg-terminal-exec runs for a
# Terminal=true entry, a window of the resident ghostty over d-bus. a hung instance (gtk main loop stuck: d-bus still
# answers a ping, every action times out after 25s) or a missing one gets a kitty window instead, else the launch
# opens nothing

def ghostty-answers []: nothing -> bool {
    (^timeout 3 gdbus call --session --timeout 2 --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty
        --method org.gtk.Actions.List | complete).exit_code == 0
}

# ghostty's options as kitty's, up to -e; what follows -e is the command
def kitty-args [args: list<string>]: nothing -> list<string> {
    let split = $args | enumerate | where item == "-e" | get --optional 0.index
    let options = if $split == null { $args } else { $args | first $split }
    let command = if $split == null { [] } else { $args | skip ($split + 1) }
    let mapped = $options | each {|arg|
        if ($arg | str starts-with "--title=") {
            [--title ($arg | str replace "--title=" "")]
        } else if ($arg | str starts-with "--working-directory=") {
            [--directory ($arg | str replace "--working-directory=" "")]
        } else { [$arg] }
    } | flatten
    $mapped ++ $command
}

def --wrapped main [...args: string]: nothing -> nothing {
    if (ghostty-answers) { exec /usr/bin/ghostty +new-window ...$args }
    exec kitty ...(kitty-args $args)
}
