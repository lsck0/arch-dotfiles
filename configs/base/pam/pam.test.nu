#!/usr/bin/env -S nu --no-config-file
# sudo's factor order from the stock stack: the terminal gate, the YubiKey (sufficient), the finger where one can be
# taken, then system-auth's password; never nouserok, so a user without a key falls through to the password. A second
# pass changes nothing. system-auth loses pambase's homed lines unless a jump crosses one.

use std/assert
use mod.nu [sudo-lines system-auth-lines u2f-line]

const STOCK = ["#%PAM-1.0" "" "auth\t\tinclude\t\tsystem-auth" "account\t\tinclude\t\tsystem-auth" "session\t\tinclude\t\tsystem-auth"]

# The module each auth line loads (an include as include:<target>), in stack order.
def auth-order [lines: list<string>]: nothing -> list<string> {
    $lines | where $it =~ '^-?auth\s' | each {|l|
        let w = $l | split row --regex '\s+'
        if ($w.1 == include) { $"include:($w.2)" } else { $w.2 }
    }
}

# pambase's system-auth, abridged to the rule lines.
const SYSTEM_AUTH = [
    "#%PAM-1.0"
    "auth       required                    pam_faillock.so      preauth"
    "-auth      [success=2 default=ignore]  pam_systemd_home.so"
    "auth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok"
    "auth       [default=die]               pam_faillock.so      authfail"
    "auth       optional                    pam_permit.so"
    "-account   [success=1 default=ignore]  pam_systemd_home.so"
    "account    required                    pam_unix.so"
    "-password  [success=1 default=ignore]  pam_systemd_home.so"
    "password   required                    pam_unix.so          try_first_pass nullok shadow"
    "-session   optional                    pam_systemd_home.so"
    "session    required                    pam_unix.so"
]

def homed-cases [] {
    let dropped = system-auth-lines $SYSTEM_AUTH
    assert equal $dropped ($SYSTEM_AUTH | where not ($it =~ pam_systemd_home)) "stock: homed lines stay"
    assert equal (system-auth-lines $dropped) $dropped "stock: second pass changed it"
    # an own jump over the homed line: dropping it would move where the jump lands
    let crossing = $SYSTEM_AUTH | insert 1 "auth       [success=2 default=ignore]  pam_localuser.so"
    assert equal (system-auth-lines $crossing) $crossing "a jump across a homed line: the stack changed"
    # a jump counts its own type's lines only: this one skips account's pam_unix, not password's homed line after it
    let other = $SYSTEM_AUTH | insert 8 "account    [success=1 default=ignore]  pam_localuser.so"
    assert equal (system-auth-lines $other | where $it =~ pam_systemd_home) [] "an account jump kept a homed line"
}

def main [] {
    homed-cases
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
