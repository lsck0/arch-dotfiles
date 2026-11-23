#!/usr/bin/env -S nu --no-config-file
# sudo's factor order from the stock stack: the terminal gate, the YubiKey (sufficient), the finger where one can be
# taken, then system-auth's password; never nouserok, so a user without a key falls through to the password. A second
# pass changes nothing.

use std/assert
use mod.nu [sudo-lines u2f-line]

const STOCK = ["#%PAM-1.0" "" "auth\t\tinclude\t\tsystem-auth" "account\t\tinclude\t\tsystem-auth" "session\t\tinclude\t\tsystem-auth"]

# The module each auth line loads (an include as include:<target>), in stack order.
def auth-order [lines: list<string>]: nothing -> list<string> {
    $lines | where $it =~ '^-?auth\s' | each {|l|
        let w = $l | split row --regex '\s+'
        if ($w.1 == include) { $"include:($w.2)" } else { $w.2 }
    }
}

def main [] {
    let line = u2f-line "pam://lsck0"
    let older = $STOCK | insert 2 "auth       sufficient pam_u2f.so cue origin=pam://old appid=pam://old"
    let with_finger = sudo-lines $STOCK true $line true
    let cases = [
        [what before u2f fprint order];
        ["key and finger" $STOCK true true [pam_succeed_if.so pam_u2f.so pam_fprintd.so include:system-auth]]
        ["key only" $STOCK true false [pam_succeed_if.so pam_u2f.so include:system-auth]]
        ["no pam_u2f installed" $STOCK false false [pam_succeed_if.so include:system-auth]]
        ["finger without pam_u2f" $STOCK false true [pam_succeed_if.so pam_fprintd.so include:system-auth]]
        ["the finger unenrolled since" $with_finger true false [pam_succeed_if.so pam_u2f.so include:system-auth]]
        ["an older key line replaced" $older true true [pam_succeed_if.so pam_u2f.so pam_fprintd.so include:system-auth]]
    ]
    for c in $cases {
        let once = sudo-lines $c.before $c.u2f $line $c.fprint
        let order = auth-order $once
        assert equal $order $c.order $"($c.what): auth order ($order | to nuon), wants ($c.order | to nuon)"
        assert not ($once | any { $in =~ nouserok }) $"($c.what): nouserok in the stack"
        assert (not $c.u2f or $line in $once) $"($c.what): the key line is not the module's"
        let gate = $once | where $it =~ pam_succeed_if | first
        assert ($gate =~ '^auth\s+requisite\s' and ($gate | str contains "tty =~ ?*")) $"($c.what): terminal gate is ($gate)"
        assert ($once | any { $in =~ '^account\s+include\s+system-auth' }) $"($c.what): account stack lost"
        let twice = sudo-lines $once $c.u2f $line $c.fprint
        assert equal $twice $once $"($c.what): second pass changed ($once | to nuon) to ($twice | to nuon)"
    }
}
