#!/usr/bin/env -S nu --no-config-file
# homelab-render on a fixture lab.json (the values, deterministic whatever the zones' order, refusals), homelab-stale
# and homelab-write against a throwaway repo, homelab-lab-path and homelab-lab-load with and without a checkout, and
# the committed platforms/homelab.nu's iso signer matching archrepo.asc and the docs that pin it.
use homelab.nu [homelab-render homelab-stale homelab-write homelab-lab-path homelab-lab-load homelab-subnet-glob HOMELAB_FILE]
use ../../platforms/homelab.nu [HOMELAB]
use std/assert

const REPO = path self ../..
const ARCHREPO_KEY = "configs/base/pacman/archrepo.asc"
# where a person checking the iso's .sig by hand reads the signer
const SIGNER_DOCS = [README.md skills/l-dotfiles-install/SKILL.md]
const LAB = {
    schema: 1
    domain: lab.test
    router: "192.0.2.1"
    proxmox: {ip: "192.0.2.2", url: "https://proxmox.lab.test"}
    zones: {
        internal: {subnet: "10.9.0.0/24", router: "10.9.0.1", ingress: null}
        external: {subnet: "10.8.0.0/24", router: "10.8.0.1", ingress: null}
    }
    nas: {ip: "10.9.0.5", smb: "//10.9.0.5/share", syncthing: "tcp://10.9.0.5:22000"}
    mirror: {
        arch: "http://10.9.0.5:8090/archlinux/$repo/os/$arch"
        lsck0: "https://mirror.lab.test/$arch"
        isoSigner: "0123456789ABCDEF0123456789ABCDEF01234567"
    }
    guests: {}
    routes: {}
}
const WANT = {
    domain: lab.test
    router: "192.0.2.1"
    hypervisor: "192.0.2.2"
    subnets: ["10.8.0.0/24" "10.9.0.0/24"]
    ssh_hosts: ["10.8.0.*" "10.9.0.*" "192.0.2.1" "192.0.2.2"]
    nas: {ip: "10.9.0.5", smb: "//10.9.0.5/share", syncthing: "tcp://10.9.0.5:22000"}
    mirror: {
        arch: "http://10.9.0.5:8090/archlinux/$repo/os/$arch"
        lsck0: "https://mirror.lab.test/$arch"
        isoSigner: "0123456789ABCDEF0123456789ABCDEF01234567"
    }
}

# The HOMELAB constant a rendered file exports, read back the way a module imports it.
def rendered-values [text: string]: nothing -> record {
    let dir = mktemp --directory
    let file = $dir | path join homelab.nu
    $text | save $file
    let values = ^nu --no-config-file -c $"use ($file) [HOMELAB]; $HOMELAB | to nuon" | from nuon
    rm --recursive --force $dir
    $values
}

def render-cases []: nothing -> nothing {
    let text = homelab-render $LAB
    assert equal (rendered-values $text) $WANT $"render: (rendered-values $text | to nuon)"
    let reordered = $LAB | update zones { transpose zone z | reverse | transpose --header-row --as-record }
    assert equal (homelab-render $reordered) $text "render: the zones' order changes the output"
    let refused = [
        [name lab];
        [schema ($LAB | update schema 2)]
        [no-zones ($LAB | update zones {})]
        [router ($LAB | update router "router.lab.test")]
        [signer ($LAB | update mirror.isoSigner "88042efb")]
        [mirror ($LAB | reject mirror)]
        [subnet ($LAB | update zones.internal.subnet "10.9.0.0/20")]
    ]
    for c in $refused {
        assert not (try { homelab-render $c.lab; true } catch { false }) $"render: ($c.name) rendered"
    }
    assert equal (homelab-subnet-glob "10.0.0.0/8") "10.*" "glob: 10.0.0.0/8"
}

def stale-cases []: nothing -> nothing {
    let dir = mktemp --directory
    let repo = $dir | path join repo
    let lab = $dir | path join lab.json
    mkdir ($repo | path join platforms)
    $LAB | to json | save $lab
    assert (homelab-stale $repo $lab) "stale: a missing file is not stale"
    assert not (homelab-stale $repo null) "stale: no checkout is stale"
    homelab-write $repo $lab
    assert not (homelab-stale $repo $lab) "stale: just written"
    $LAB | update nas.ip "10.9.0.6" | to json | save --force $lab
    assert (homelab-stale $repo $lab) "stale: a changed lab.json is not stale"
    let before = open --raw ($repo | path join $HOMELAB_FILE)
    homelab-write $repo null
    assert equal (open --raw ($repo | path join $HOMELAB_FILE)) $before "write: no checkout changed the file"
    rm --recursive --force $dir
}

def lab-path-cases []: nothing -> nothing {
    let dir = mktemp --directory
    assert equal (with-env {HOMELAB_DIR: $dir} { homelab-lab-path }) null "lab path: an empty checkout dir has a lab.json"
    let lab = $dir | path join src generated lab.json
    mkdir ($lab | path dirname)
    "{}" | save $lab
    assert equal (with-env {HOMELAB_DIR: $dir} { homelab-lab-path }) $lab "lab path: the checkout's lab.json not found"
    assert equal (with-env {HOMELAB_DIR: $dir} { homelab-lab-load }) null "lab load: a lab.json without a schema loaded"
    $LAB | to json | save --force $lab
    assert equal (with-env {HOMELAB_DIR: $dir} { homelab-lab-load }) $LAB "lab load: the checkout's lab.json not loaded"
    rm --recursive --force $dir
}

def signer-case []: nothing -> nothing {
    let home = mktemp --directory
    let shown = do { ^gpg --homedir $home --show-keys --with-colons ($REPO | path join $ARCHREPO_KEY) } | complete
    let fingerprint = $shown.stdout | lines | parse "fpr:{rest}" | get 0.rest | split row ":" | get 8
    rm --recursive --force $home
    assert equal $fingerprint $HOMELAB.mirror.isoSigner $"($ARCHREPO_KEY) is ($fingerprint), the lab's signer ($HOMELAB.mirror.isoSigner)"
    for doc in $SIGNER_DOCS {
        assert (open --raw ($REPO | path join $doc) | str contains $HOMELAB.mirror.isoSigner) $"($doc) does not pin the iso signer"
    }
}

def main [] {
    render-cases
    stale-cases
    lab-path-cases
    signer-case
}
