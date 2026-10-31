#!/usr/bin/env -S nu --no-config-file

# The YubiKey OATH code of the one account matching <account> onto the clipboard; without one, the accounts.
def main [account?: string]: nothing -> nothing {
    if $account == null { exec ykman oath accounts list }
    let code = ^ykman oath accounts code --single $account | str trim
    if (which wl-copy | is-empty) { print $code; return }
    $code | ^wl-copy
    print $"totp: ($account) copied"
}
