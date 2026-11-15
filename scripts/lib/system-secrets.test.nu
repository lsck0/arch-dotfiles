#!/usr/bin/env -S nu --no-config-file
# The secrets root may be handed: what the modules' meta.secrets and the platform's wireguard configs name, relative to
# configs/secrets/keys/ ({host} this machine's name), and nothing that leaves keys/ by an absolute path or a `..`.
use system.nu [system-secrets]
use std/assert

def module-write [repo: path, id: string, secrets: list<string>]: nothing -> nothing {
    let dir = $repo | path join configs ...($id | split row "/")
    mkdir $dir
    $"export const meta = {secrets: ($secrets | to nuon)}\nexport def system [cfg: record] { [] }\n" | save --force ($dir | path join mod.nu)
}

def refused [repo: path, wireguard: any]: nothing -> string {
    try { system-secrets $repo $wireguard | ignore; "" } catch {|e| $e.msg }
}

def check [work: path]: nothing -> nothing {
    let repo = $work | path join repo
    let host = sys host | get hostname
    module-write $repo base/ssh ["ssh-host/{host}/ssh_host_ed25519_key" "shared/token"]
    module-write $repo base/plain []
    module-write $repo other/again ["shared/token"]
    let got = system-secrets $repo ["wireguard/pc.conf" ""] | sort
    assert equal $got ["shared/token" $"ssh-host/($host)/ssh_host_ed25519_key" "wireguard/pc.conf"] $"declared secrets: ($got | to nuon)"
    assert equal (system-secrets $repo null | sort) ["shared/token" $"ssh-host/($host)/ssh_host_ed25519_key"] "no wireguard config"

    for outside in ["/etc/shadow" "../state/app/token" "wireguard/../../../.git/config"] {
        let message = refused $repo $outside
        assert ($message | str contains $"secrets outside keys/: ($outside)") $"wireguard ($outside): ($message | to nuon)"
    }
    module-write $repo base/escapes ["ssh-host/{host}/../../../yubikey/u2f_keys"]
    assert (refused $repo null | str contains "secrets outside keys/") "a module's meta.secrets left keys/"
}

def main []: nothing -> nothing {
    let work = mktemp --directory --tmpdir dot-system-secrets-test-XXXXXX
    let outcome = try {
        with-env {XDG_CACHE_HOME: ($work | path join cache)} { check $work }
        null
    } catch {|e| $e }
    rm --recursive --force $work
    if $outcome != null { error make $outcome }
}
