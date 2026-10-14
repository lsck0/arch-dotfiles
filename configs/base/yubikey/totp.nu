#!/usr/bin/env -S nu --no-config-file
# a touch-required account blinks the key first

# The YubiKey OATH code of the one account matching <account> onto the clipboard; without one, the accounts.
def main [account?: string]: nothing -> nothing {
    if $account == null { exec ykman oath accounts list }
    ^ykman oath accounts code --single $account | str trim | ^wl-copy
    print $"totp: ($account) copied"
}
