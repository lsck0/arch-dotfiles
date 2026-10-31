#!/usr/bin/env -S nu --no-config-file
# The first login after a reinstall: restores the Proton sign-ins before any app starts, once the keyring is open.

const HERE = path self | path expand | path dirname
const REPO = $HERE | path join .. .. .. .. | path expand
use ($HERE | path join sessions.nu) [sessions-restore sessions-settled MARKER]
use ($REPO | path join scripts lib state.nu) [xdg]
use ($REPO | path join scripts lib secrets.nu) [secret-is-plaintext OWNER_WITNESS]

def main [] {
    if not (secret-is-plaintext ($REPO | path join $OWNER_WITNESS)) {
        print "dotfiles secrets locked: dot apply core/proton/sessions restores once they are unlocked"
        return
    }
    let archives = $REPO | path join configs secrets keys proton (sys host | get hostname)
    let statuses = sessions-restore $archives
    $statuses | where status != none | each {|row| print $"($row.app): ($row.status)" } | ignore
    if (sessions-settled $statuses) {
        mkdir (xdg state $MARKER | path dirname)
        touch (xdg state $MARKER)
    }
}
