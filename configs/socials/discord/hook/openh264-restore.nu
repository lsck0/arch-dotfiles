#!/usr/bin/env -S nu --no-config-file
# discord's host points the voice engine at one openh264 build, but its web client keeps another and deletes the
# host's as unused on every start: put the host's back, from cisco's binary pinned here

use ../../../../scripts/lib/state.nu [xdg]

const REPO = path self | path dirname | path join ../../../.. | path expand
const URL = "https://ciscobinary.openh264.org"
# sha256 of the .bz2 cisco serves, per library name the host asks for
const PINS = {
    "libopenh264-2.5.1-linux64.7.so": "82e436db8606433e3f823c7fff3269c43b3ba3f12510a851ef7b156b80ad1b11"
    "libopenh264-2.7.0-linux64.8.so": "44ad0dd2c5af2bac84d26f89f2eb4e268708b8739323d15d33837f7221ce4980"
}

def main []: nothing -> nothing {
    let cache = xdg cache discord-openh264
    let host = xdg config discord Discord
    if not ($host | path exists) { return }
    let modules = $host | path expand | path dirname | path join modules
    let core = glob ($modules | path join discord_desktop_core-*) | sort --natural | last 1 | get --optional 0
    let asar = $core | default "" | path join discord_desktop_core core.asar
    if $core == null or not ($asar | path exists) { return }
    let name = open --raw $asar | parse --regex '(?<n>libopenh264-[0-9.]+-linux64\.[0-9]+\.so)' | get --optional 0.n
    if $name == null { return }
    let dest = xdg config discord discord_asset_cache openh264 $name
    if ($dest | path exists) { return }
    let sha = $PINS | get --optional $name
    if $sha == null {
        print --stderr $"Discord wants an unpinned openh264 ($name): add its sha256 to PINS in openh264-restore.nu"
        exit 1
    }
    let bz2 = $cache | path join $"($name).bz2"
    ^nu --no-config-file ($REPO | path join scripts dot.nu) internal fetch file $"($URL)/($name).bz2" $sha $bz2
    mkdir ($dest | path dirname)
    ^bunzip2 --stdout $bz2 | save --force --raw $"($dest).new"
    mv --force $"($dest).new" $dest
}
