#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname | path join .. .. ..
use ($REPO | path join scripts lib secrets.nu) [secret-is-plaintext]

const STALE_DAYS = 3
const CHECK_DAYS = 7
const RESTORE_DAYS = 30
const LOCK_WAIT_S = 600
const CANARY_BYTES = 4096
const NM_METERED = [
    org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Metered
]
const METERED = ["1" "3"]
const EXCLUDES = [
    sync downloads Downloads .cache .local/share/Trash .local/share/baloo ".var/app/*/cache"
    .steam .local/share/Steam .local/share/flatpak .local/share/containers
    .local/share/xlcore/ffxiv .local/share/xlcore/wineprefix .local/share/xlcore/compatibilitytool
    .local/share/xlcore/runtime .local/share/xlcore/dalamud .local/share/xlcore/dalamudAssets
    .local/share/xlcore/installedPlugins .local/share/xlcore/logs
    .local/share/libvirt/images .local/share/gnome-boxes .ollama/models .lmstudio/models .local/share/unreal-engine
    .gradle .m2/repository .local/share/ghcup .local/share/rustup .local/share/elan .local/share/kani
    .local/share/cargo/registry .local/share/cargo/git .local/share/dotnet .local/share/nuget
    .local/share/go/pkg go/pkg .npm .local/share/opam .local/share/mise .local/share/zinit
    .local/share/nvim/lazy .local/share/nvim/mason .local/share/torbrowser .local/share/llm-jailbreaks
    .local/share/android-sdk .local/share/android/avd
    "**/node_modules" "**/target" "**/.venv"
]

def state-dir []: nothing -> path {
    $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join borg
}

def stamp-older [name: string, days: int]: nothing -> bool {
    let stamp = state-dir | path join $name
    not ($stamp | path exists) or (ls $stamp | get 0.modified) < ((date now) - ($days * 1day))
}

def skip-run [why: string]: nothing -> nothing {
    print --stderr $"borg: ($why), skipping"
    if (stamp-older last-success $STALE_DAYS) {
        let stamp = state-dir | path join last-success
        let last = if ($stamp | path exists) { ls $stamp | get 0.modified | format date "%F %H:%M" } else { "never" }
        print --stderr $"borg: no backup in the last ($STALE_DAYS) days \(last: ($last)\)"
        exit 1
    }
    exit 0
}

def fail [message: string]: nothing -> nothing {
    print --stderr $"borg: ($message)"
    exit 1
}

def --wrapped succeeds [...argv: string]: nothing -> bool {
    (do { ^$argv.0 ...($argv | skip 1) } | complete).exit_code == 0
}

def --wrapped borg [...args: string] {
    ^borg --lock-wait $LOCK_WAIT_S ...$args
}

def repo-open [folder: path, host: string]: nothing -> path {
    # one repo per init, named by its creation: a reinstalled host starts a new one beside the copy the NAS still has
    let repos = glob ($folder | path join $"($host)-*" config) | path dirname
    if ($repos | length) > 1 { error make {msg: $"several repos in ($folder) \(($repos | str join ' ')\), keep one"} }
    if ($repos | is-not-empty) { return $repos.0 }
    let repo = $folder | path join $"($host)-(date now | format date '%Y%m%d%H%M%S')"
    with-env {BORG_REPO: $repo} { borg init --encryption=repokey-blake2 }
    $repo
}

def archive [folder: path, secrets: path, canary: path]: nothing -> int {
    $env.BORG_REPO = repo-open $folder (sys host | get hostname)
    # the key lives in the repo's config, a damaged config loses every archive: keep a (passphrase-encrypted) copy
    let key = $secrets | path join $"borg-key-($env.BORG_REPO | path basename)"
    if not ($key | path exists) or (ls $key | get 0.size) == 0b {
        let text = borg key export $env.BORG_REPO
        touch $key
        chmod 600 $key
        $text | save --force $key
    }
    ^nu --no-config-file ($env.DOTFILES | path join scripts dot.nu) internal backup
    let excludes = $EXCLUDES | each {|p| $nu.home-dir | path join $p } | prepend $folder | each { $"--exclude=($in)" }
    let rc = try {
        (borg create --stats --compression auto,zstd,3 --exclude-caches --one-file-system --exclude-if-present .nobackup
            ...$excludes "::{hostname}-{now:%Y%m%d-%H%M%S}" $nu.home-dir)
        0
    } catch {|e| $e.exit_code? | default 2 }
    # 1 is a warning (a file changed while read), routine for a live home; the archive exists
    if $rc > 1 { return $rc }
    borg prune --glob-archives "{hostname}-*" --keep-daily 7 --keep-weekly 4 --keep-monthly 6
    borg compact
    touch (state-dir | path join last-success)
    if (stamp-older last-check $CHECK_DAYS) {
        borg check --repository-only
        touch (state-dir | path join last-check)
    }
    if (stamp-older last-restore $RESTORE_DAYS) {
        let last = borg list --last 1 --short | str trim
        let restored = borg extract --stdout $"::($last)" ($canary | str trim --left --char "/") | into binary
        if $restored != (open --raw $canary) {
            error make {msg: $"restoring ($canary) from ($last) did not give the file back"}
        }
        touch (state-dir | path join last-restore)
    }
    0
}

def main []: nothing -> nothing {
    $env.DOTFILES = $env.DOTFILES? | default ($nu.home-dir | path join projects arch-dotfiles)
    let host = sys host | get hostname
    # same path and id as configs/core/syncthing
    let folder = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join borg-repo
    let folder_id = $"borg-($host)"
    let secrets = $env.DOTFILES_SECRETS? | default ($env.DOTFILES | path join configs secrets keys)
    let passfile = $secrets | path join borg-passphrase
    let canary = state-dir | path join canary

    # the same test as ConditionACPower=, here so a skipped run still reports a stale backup
    if not (succeeds systemd-ac-power) { skip-run "on battery" }
    let metered = do { ^busctl get-property ...$NM_METERED } | complete
    if $metered.exit_code == 0 and ($metered.stdout | str trim | split row " " | last) in $METERED {
        skip-run "metered connection"
    }
    if not ($passfile | path exists) or (ls $passfile | get 0.size) == 0b {
        fail "no passphrase, create configs/secrets/keys/borg-passphrase (configs/core/borg/README.md)"
    }
    # a locked blob would become the passphrase of a fresh repo
    if not (secret-is-plaintext $passfile) { fail "secrets are locked, unlock them (dot secrets unlock)" }

    $env.BORG_PASSCOMMAND = $"cat '($passfile)'"
    $env.BORG_RELOCATED_REPO_ACCESS_IS_OK = "no"
    $env.BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK = "no"
    $env.BORG_EXIT_CODES = "legacy"
    mkdir (state-dir) $folder
    # a fresh random file that never changes: the monthly restore check extracts it and compares
    if not ($canary | path exists) or (ls $canary | get 0.size) == 0b {
        random binary $CANARY_BYTES | save --force $canary
    }

    # syncthing must not ship a half-written transaction
    let paused = if (succeeds systemctl --user -q is-active syncthing.service) {
        let folders = do { ^syncthing cli config folders list } | complete
        if $folders.exit_code != 0 { fail "syncthing runs but its api does not answer, not writing under it" }
        if $folder_id in ($folders.stdout | lines) {
            ^syncthing cli config folders $folder_id paused set true
            true
        } else {
            print --stderr $"borg: no syncthing folder ($folder_id), this backup stays on this machine"
            false
        }
    } else { false }
    let rc = try { archive $folder $secrets $canary } catch {|e|
        print --stderr $"borg: ($e.msg)"
        $e.exit_code? | default 1
    }
    if $paused and not (succeeds syncthing cli config folders $folder_id paused set "false") {
        print --stderr $"borg: could not resume syncthing folder ($folder_id)"
    }
    exit $rc
}
