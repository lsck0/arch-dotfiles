#!/usr/bin/nu --no-config-file
const KNOB = "/proc/sys/kernel/split_lock_mitigate"

def set-knob [value: string]: nothing -> nothing {
    if ($KNOB | path exists) { $value | save --force $KNOB }
}

def main []: nothing -> nothing {
    print --stderr "usage: split-lock-mitigate on|off"
    exit 2
}

def "main on" []: nothing -> nothing { set-knob "1" }

def "main off" []: nothing -> nothing { set-knob "0" }
