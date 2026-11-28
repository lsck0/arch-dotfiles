#!/usr/bin/env -S nu --no-config-file
# tablet-driver.py's offline decode test (scripts/test-driver.py): FIFOs stand in for the tablet's two HID nodes.

const TEST = path self scripts/test-driver.py

def main [] {
    # python-evdev comes with this module's packages: a machine without them has no driver to test
    if (^python3 -c "import evdev" | complete).exit_code != 0 { return }
    let run = ^python3 -I -B $TEST | complete
    if $run.exit_code == 0 { return }
    let failed = $run.stdout | lines | where $it =~ '^FAIL'
    let why = if ($failed | is-empty) { $run.stderr | str trim | lines | last 3 } else { $failed }
    error make {msg: $"tablet-driver.test: ($why | str join '; ')"}
}
