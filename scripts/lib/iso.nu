# the lsck0 install iso: archiso's releng profile plus mirror/iso (packages, airootfs overlay, profiledef), the [lsck0]
# repo and key from configs/base/pacman, and a verified shallow checkout of this repo as the installer's launcher.
# network: the arch mirrors (or --mirror) for the packages; nothing else, the checkout comes from the local repo

use log.nu *

const REPO = path self ../..
const RELENG = "/usr/share/archiso/configs/releng"
const OVERLAY = "mirror/iso"
const APPEND_SUFFIX = ".append"
const PACMAN_CONF = "configs/base/pacman/pacman.conf"
const LSCK0_KEY = "configs/base/pacman/archrepo.asc"
const LSCK0_SECTION = "[lsck0]"
const KEYRING_DIR = "usr/share/pacman/keyrings"
const LAUNCHER_DIR = "usr/share/lsck0/arch-dotfiles"
const BOOTSTRAP = "bootstrap.sh"
const ISO_NAME = "archlinux-lsck0"
const ISO_ARCH = "x86_64"
const ISO_LATEST = $"($ISO_NAME)-latest-($ISO_ARCH).iso"
const ISO_PATTERN = '^archlinux-lsck0-\d{4}\.\d{2}\.\d{2}-x86_64\.iso$'
const WORK_DEFAULT = ".cache/dotfiles-iso"

def --wrapped as-root [...argv: string]: nothing -> nothing {
    if (is-admin) { run-external ...$argv } else { run-external sudo ...$argv }
}

def bootstrap-const [name: string]: nothing -> string {
    open --raw ($REPO | path join $BOOTSTRAP) | parse --regex ('(?m)^' + $name + '=(?<v>\S+)$') | get 0.v
}

# the same check bootstrap.sh runs on its clone, here on the commit the iso bakes
def checkout-verify [dir: path]: nothing -> nothing {
    let fingerprint = bootstrap-const SIGNING_KEY_FINGERPRINT
    let gnupg = mktemp --directory
    ^gpg --homedir $gnupg --batch -q --import ($dir | path join (bootstrap-const SIGNING_KEY_FILE))
    let r = with-env {GNUPGHOME: $gnupg} { ^git -C $dir verify-commit --raw HEAD | complete }
    rm --recursive --force $gnupg
    if not ($r.stderr | lines | any {|l| $l =~ $'^\[GNUPG:\] VALIDSIG .* ($fingerprint)$' }) {
        error make {msg: $"iso: HEAD (^git -C $dir rev-parse --short HEAD | str trim) is not signed by ($fingerprint), the iso bakes only a signed commit"}
    }
}

def keyring-write [dir: path]: nothing -> nothing {
    let key = $REPO | path join $LSCK0_KEY
    let gnupg = mktemp --directory
    let fingerprint = ^gpg --homedir $gnupg --show-keys --with-colons $key | lines | parse "fpr:{rest}" | get 0.rest | split row ":" | get 8
    rm --recursive --force $gnupg
    mkdir $dir
    cp $key ($dir | path join lsck0.gpg)
    $"($fingerprint):4:\n" | save --force ($dir | path join lsck0-trusted)
}

# last, unlike the installed system's: pacstrap reads the live pacman.conf, and core and extra must win there
def pacman-live [releng_conf: path]: nothing -> string {
    let section = open --raw ($REPO | path join $PACMAN_CONF) | lines | reduce --fold {inside: false, out: []} {|l, acc|
        let inside = if ($l | str starts-with "[") { $l == $LSCK0_SECTION } else { $acc.inside }
        {inside: $inside, out: (if $inside { $acc.out | append $l } else { $acc.out })}
    } | get out | str join "\n"
    $"(open --raw $releng_conf | str trim --right)\n\n($section | str trim --right)\n"
}

def profile-write [profile: path, launcher: path, mirror: any]: nothing -> nothing {
    let overlay = $REPO | path join $OVERLAY
    rm --recursive --force $profile
    cp --recursive $RELENG $profile
    mv ($profile | path join profiledef.sh) ($profile | path join profiledef.releng.sh)
    cp ($overlay | path join profiledef.sh) ($profile | path join profiledef.sh)
    let packages = open --raw ($profile | path join packages.x86_64) | lines | append (open --raw ($overlay | path join packages.x86_64) | lines)
        | where {|l| $l != "" and not ($l | str starts-with "#") } | uniq | sort
    $"($packages | str join "\n")\n" | save --force ($profile | path join packages.x86_64)
    let root = $profile | path join airootfs
    for f in (glob ($overlay | path join airootfs "**" "*") --no-dir) {
        let rel = $f | path relative-to ($overlay | path join airootfs)
        if ($rel | str ends-with $APPEND_SUFFIX) {
            let target = $root | path join ($rel | str substring 0..<(($rel | str length) - ($APPEND_SUFFIX | str length)))
            $"(open --raw $target | str trim --right)\n\n(open --raw $f)" | save --force $target
        } else {
            mkdir ($root | path join $rel | path dirname)
            cp $f ($root | path join $rel)
        }
    }
    pacman-live ($profile | path join pacman.conf) | save --force ($root | path join etc pacman.conf)
    keyring-write ($root | path join $KEYRING_DIR)
    mkdir ($root | path join $LAUNCHER_DIR | path dirname)
    mv $launcher ($root | path join $LAUNCHER_DIR)
    if $mirror != null {
        let list = $profile | path join mirrorlist
        $"Server = ($mirror)\n" | save --force $list
        open --raw ($profile | path join pacman.conf) | str replace --all "/etc/pacman.d/mirrorlist" $list | save --force ($profile | path join pacman.conf)
    }
}

def launcher-clone [dest: path]: nothing -> nothing {
    rm --recursive --force $dest
    # no submodules, no lfs objects: the installer needs only bootstrap.sh and the key, the bootstrap clones master
    with-env {GIT_LFS_SKIP_SMUDGE: "1"} {
        ^git -c submodule.recurse=false clone -q --depth 1 --no-recurse-submodules --no-tags $"file://($REPO)" $dest
    }
    checkout-verify $dest
}

def outputs-publish [built: path, out: path, keep: int, sign: any]: nothing -> list<path> {
    mkdir $out
    let iso = $out | path join ($built | path basename)
    mv --force $built $iso
    let sum = ^sha256sum $iso | split row " " | first
    $"($sum)  ($iso | path basename)\n" | save --force $"($iso).sha256"
    let latest = $out | path join $ISO_LATEST
    ^ln -sfn ($iso | path basename) $latest
    $"($sum)  ($ISO_LATEST)\n" | save --force $"($latest).sha256"
    let signed = if $sign == null { [] } else {
        ^gpg --batch --yes --local-user $sign --detach-sign --output $"($iso).sig" $iso
        ^ln -sfn $"($iso | path basename).sig" $"($latest).sig"
        [$"($iso).sig"]
    }
    let old = ls $out | get name | where {|f| ($f | path basename) =~ $ISO_PATTERN } | sort --reverse | skip $keep
    for f in $old { rm --force $f $"($f).sha256" $"($f).sig" }
    [$iso $"($iso).sha256" $latest] ++ $signed
}

export def iso-build [out: any, work: any, mirror: any, sign: any, keep: int]: nothing -> nothing {
    if (which mkarchiso | is-empty) { error make {msg: "iso: mkarchiso missing (pacman -S archiso, declared by qemu/libvirt)"} }
    let work = $work | default $env.DOT_ISO_WORK? | default ($nu.home-dir | path join $WORK_DEFAULT) | path expand
    let out = $out | default ($work | path join out) | path expand
    let profile = $work | path join profile
    let build = $work | path join build
    let staging = $work | path join staging
    mkdir $work
    log-info $"iso: baking a verified checkout of (^git -C $REPO rev-parse --short HEAD | str trim)"
    launcher-clone ($work | path join launcher)
    profile-write $profile ($work | path join launcher) $mirror
    # mkarchiso resumes from its markers, so a stale build dir would ship the last run's root
    as-root rm --recursive --force $build $staging
    log-info "iso: mkarchiso (several minutes)"
    as-root mkarchiso -v -r -w $build -o $staging $profile
    let built = glob ($staging | path join $"($ISO_NAME)-*-($ISO_ARCH).iso") | get 0
    if not (is-admin) { as-root chown --recursive $"(^id -u | str trim):(^id -g | str trim)" $staging }
    let outputs = outputs-publish $built $out $keep $sign
    as-root rm --recursive --force $staging $profile
    $outputs | each { print $in } | ignore
}
