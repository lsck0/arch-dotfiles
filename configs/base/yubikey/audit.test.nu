#!/usr/bin/env -S nu --no-config-file
# secret-class takes the first glob that matches, so CLASSES is ordered: a narrower glob after the wider one that
# covers it would never be reached, and its credential would age unaudited. And declared-findings: a meta.secrets
# entry keys/ lacks under any host is a fail (root is handed only what exists), an UNBACKED one a note.
use audit.nu [CLASSES secret-class declared-findings]
use std/assert

def class-cases []: nothing -> nothing {
    let cases = [
        [path class];
        [initramfs-ssh/host/sshkeydir/.ed25519.sk ssh]
        [initramfs-ssh/host/sshkeydir/ed25519.pk "-"]
        [syncthing/host/key.pem identity]
        [syncthing/gui-password password]
        [syncthing/host/cert.pem "-"]
        [wireguard/pc.conf wireguard]
        [wireguard/phone.png "-"]
        [pgp/private.asc identity]
        [pgp/other-public.asc "-"]
        [alloy/host api]
        [unknown/file ""]
    ]
    for c in $cases { assert equal (secret-class $c.path) $c.class $c.path }
    # no glob stands behind one that swallows it: a path made from it gets its own class
    for row in $CLASSES {
        let path = $row.glob | str replace --all "*" "x"
        assert equal (secret-class $path) $row.class $"($row.glob) is shadowed by an earlier glob"
    }
}

def declared-cases []: nothing -> nothing {
    let hosts = [pc notebook]
    let held = [wifi alloy/pc alloy/notebook initramfs-ssh/pc/sshkeydir/.ed25519.sk]
    let cases = [
        [name declared fails notes];
        ["held" [{module: a, entry: wifi} {module: a, entry: "alloy/{host}"}] [] 0]
        ["renamed" [{module: a, entry: "alloy-{host}"}] [alloy-pc alloy-notebook] 0]
        ["missing for one host" [{module: a, entry: "syncthing/{host}/key.pem"}] [syncthing/pc/key.pem syncthing/notebook/key.pem] 0]
        ["missing without a host" [{module: a, entry: samba}] [samba] 0]
        ["not backed up yet" [{module: a, entry: "ssh-host/{host}/key"} {module: a, entry: "ssh-host/{host}/other"}] [] 1]
    ]
    for c in $cases {
        let found = declared-findings $c.declared $hosts $held
        let fails = $found | where level == fail | get text | parse --regex 'keys/(?<path>[^,]+),' | get path
        assert equal $fails $c.fails $"($c.name): fails"
        assert equal ($found | where level == note | length) $c.notes $"($c.name): notes"
        assert equal ($found | where level == ok) [] $"($c.name): nothing to report as ok"
    }
}

def main []: nothing -> nothing {
    class-cases
    declared-cases
}
