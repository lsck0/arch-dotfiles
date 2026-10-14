#!/usr/bin/nu --no-config-file
# split lock mitigation sleeps the offending thread, and games and anticheat under proton trip it constantly

const KNOB = "/proc/sys/kernel/split_lock_mitigate"

def set-knob [value: string]: nothing -> nothing {
    # only cpus with split lock detection have the knob
    if ($KNOB | path exists) { $value | save --force $KNOB }
}

def main []: nothing -> nothing {
    print --stderr "usage: split-lock-mitigate on|off"
    exit 2
}

def "main on" []: nothing -> nothing { set-knob "1" }

def "main off" []: nothing -> nothing { set-knob "0" }
