use log.nu [log-info log-warn]
use state.nu [SYSTEM_REPO SYSTEM_STATE]
use ledger.nu [ledger-get]
use migrate.nu [migrations-list migration-run]

const REPO = path self ../..
# a target must lie on it, so root only ever runs a commit of this history
const BRANCH = "master"
# the first generations with the root copy; an older one ran its system layer from the checkout as root
const FLOOR_FILES = [scripts/lib/system-apply.sh scripts/lib/system-apply.nu]
const PACMAN_CONF = "configs/base/pacman/pacman.conf"
const PLATFORM_LOCAL = "/etc/dotfiles/platform.nuon"
const NIX = [nix --extra-experimental-features "nix-command flakes"]
const NIXPKGS_PREFIX = "github:NixOS/nixpkgs/"
const SNAPSHOT_DATE = '\d{4}-\d{2}-\d{2}'

def --wrapped git-out [...args: string]: nothing -> string { ^git -C $REPO ...$args | str trim }

def --wrapped git-ok [...args: string]: nothing -> bool { (do { ^git -C $REPO ...$args } | complete).exit_code == 0 }

def describe-commit [rev: string]: nothing -> string { git-out log -1 "--format=%s, %ci" $rev }

export def rollback-resolve [target: string]: nothing -> string {
    let sha = if $target =~ '^\d+$' {
        let matches = ^git -C $REPO log --format=%H%x09%s $BRANCH | lines | parse "{sha}\t{subject}"
            | where subject == $"Generation: ($target)"
        if ($matches | length) != 1 {
            let found = $"($matches | length) commits named 'Generation: ($target)' on ($BRANCH)"
            error make {msg: $"($found), need exactly one"}
        }
        $matches.0.sha
    } else {
        let found = do { ^git -C $REPO rev-parse --verify --quiet $"($target)^{commit}" } | complete
        if $found.exit_code != 0 { error make {msg: $"'($target)' is neither a generation number nor a commit"} }
        $found.stdout | str trim
    }
    if not (git-ok merge-base --is-ancestor $sha $BRANCH) {
        error make {msg: $"($sha) is not on ($BRANCH); only a generation of its history can be rolled back to"}
    }
    if not ($FLOOR_FILES | any {|f| git-ok cat-file -e $"($sha):($f)" }) {
        error make {msg: $"($sha) predates the root copy, its system layer would run as root from the checkout"}
    }
    $sha
}

# the machine's own platform file wins, as at load
def platform-pin [sha: string]: nothing -> string {
    let host = sys host | get hostname
    let text = if ($PLATFORM_LOCAL | path exists) { open --raw $PLATFORM_LOCAL } else {
        do { ^git -C $REPO show $"($sha):platforms/($host).nuon" } | complete | get stdout
    }
    try { $text | from nuon | get facts.lsck0_snapshot? | default "" } catch { "" }
}

# nothing when the mirror no longer keeps a snapshot that old
def mirror-snapshot [sha: string]: nothing -> string {
    let arch = ^uname -m | str trim
    let conf = git-out show $"($sha):($PACMAN_CONF)" | lines
    let section = $conf | skip until { $in == "[lsck0]" } | skip 1 | take until { $in | str starts-with "[" }
    let base = $section | parse --regex '^Server = (?<url>https://.*)/\$arch$' | get --optional 0.url
    if $base == null { error make {msg: $"no [lsck0] https Server line in ($sha):($PACMAN_CONF)"} }
    let committed = git-out log -1 --format=%ct $sha | into int
    let dates = http get --raw $"($base)/" | parse --regex ('href="(?<d>' + $SNAPSHOT_DATE + ')/"')
        | get d | uniq | sort --reverse
    $dates | where {|d|
        let published = try {
            http head $"($base)/($d)/($arch)/lsck0.db"
            | where { ($in.name | str lowercase) == "last-modified" } | get 0.value
        } catch { return false }
        ($published | into datetime | into int) // 1_000_000_000 <= $committed
    } | get --optional 0 | default ""
}

def nixpkgs-pin [rev: string]: nothing -> string {
    let pattern = $'NIXPKGS[[:space:]]*=[[:space:]]*"?($NIXPKGS_PREFIX)[0-9a-f]+'
    do { ^git -C $REPO grep -h -o -E $pattern $rev -- install.sh scripts } | complete
    | get stdout | lines | get --optional 0 | default "" | str replace --regex '^[^g]*' ''
}

# one installed by hand from the flake registry is `flake:nixpkgs`, never matched
def nix-stale [rev: string]: nothing -> list<string> {
    if (which nix | is-empty) { return [] }
    ^$NIX.0 ...($NIX | skip 1) profile list --json | from json | get elements
    | items {|name, e| {name: $name, url: $e.originalUrl? } }
    | where { ($in.url | default "" | str starts-with $NIXPKGS_PREFIX) and $in.url != $rev } | get name | sort
}

# before the nu generations, install.sh and config.sh's sudo resets the env: the pin goes on root's command line
def drivers [sha: string, pin: string]: nothing -> record {
    let dot = [nu --no-config-file scripts/dot.nu]
    # since internal.nu, install is apply --packages
    if (git-ok cat-file -e $"($sha):scripts/lib/internal.nu") {
        {root: ($dot ++ [apply --packages]), user: ($dot ++ [apply --packages --user]), apply: ($dot ++ [apply]), nu: true}
    } else if (git-ok cat-file -e $"($sha):scripts/lib/system-apply.nu") {
        {root: ($dot ++ [install]), user: ($dot ++ [install --user]), apply: ($dot ++ [apply]), nu: true}
    } else {
        let unattended = ($env.DOTFILES_UNATTENDED? | is-not-empty) or not (is-terminal --stdin)
        let entry = $SYSTEM_REPO | path join scripts lib system-apply.sh
        {
            root: ([sudo $"LSCK0_SNAPSHOT=($pin)" $entry install] ++ (if $unattended { [--unattended] } else { [] }))
            user: [./install.sh --user]
            apply: [./config.sh]
            nu: false
        }
    }
}

def copy-rollback []: nothing -> nothing {
    let script = 'source "$1/scripts/lib/system.sh" && system_copy --rollback "$1" "$2" sudo'
    if (do { ^bash -c $script rollback $REPO $SYSTEM_REPO } | complete).exit_code != 0 {
        error make {msg: $"the root copy did not step back; the checkout is detached, nothing else changed"}
    }
}

def driver-run [argv: list<string>, what: string]: nothing -> bool {
    let ok = try { ^$argv.0 ...($argv | skip 1); true } catch { false }
    if not $ok { log-warn $"($what) reported failures" }
    $ok
}

export def rollback-run [target: string, --full, --dry-run]: nothing -> nothing {
    if (is-admin) { error make {msg: "run as the admin, not root; the root half goes through sudo"} }
    if ($env.DIRENV_DIR? | is-not-empty) { error make {msg: "run outside a direnv directory"} }
    let sha = rollback-resolve $target
    let short = $sha | str substring 0..11
    # applied here, absent at the target: undone newest first, the last step before the checkout
    let later = migrations-list $REPO | where id in (ledger-get migration) | where {|m| not (git-ok cat-file -e $"($sha):($m.file | path relative-to $REPO)") }
    let stuck = $later | where not reversible
    if ($stuck | is-not-empty) { error make {msg: $"($target) predates migration ($stuck.id | str join ', '), which has no down"} }
    let label = describe-commit $sha
    let admin = ^id -nG | split row " " | any { $in == wheel }
    let dirty = git-out status --porcelain --ignore-submodules=all | lines
    log-info $"target ($short) \(($label)\)"
    log-info $"from   (git-out rev-parse HEAD | str substring 0..11) \((describe-commit HEAD)\)"
    log-info $"config layer: (git-out diff --shortstat $sha HEAD -- . ':!secrets')"
    if $admin {
        let source = try { open --raw ($SYSTEM_REPO | path join .source) | str trim } catch { "none" }
        log-info $"root copy ($SYSTEM_REPO) at ($source), stepped back to ($short)"
    } else {
        log-info "not in wheel: the user layer only"
    }
    mut pin = ""
    mut stale = []
    if $full {
        $pin = platform-pin $sha
        if $pin != "" {
            log-info $"lsck0: the target's platform file pins ($pin)"
        } else {
            $pin = mirror-snapshot $sha
            if $pin == "" {
                let why = $"the mirror keeps no [lsck0] snapshot from before ($short)"
                error make {msg: $"($why); --full cannot reproduce it, drop --full for the config layer"}
            }
            log-info $"lsck0: dated snapshot ($pin), the newest published before the commit"
        }
        let installed = with-env {DOT_LAYER: system} { ledger-get snapshot } | get --optional 0 | default unknown
        log-info $"lsck0: installed now ($installed) \(ledger\)"
        if not $admin { log-warn "not in wheel: the [lsck0] packages stay, only nix and the user parts go back" }
        let rev = nixpkgs-pin $sha
        if $rev == "" {
            log-warn "nix: the target pins no nixpkgs rev, its install adds only what is missing"
        } else {
            $stale = nix-stale $rev
            let names = if ($stale | is-empty) { "none" } else { $stale | str join " " }
            let now = nixpkgs-pin HEAD | path basename
            log-info $"nix: ($rev | path basename) \(now ($now)\), re-pinning ($stale | length): ($names)"
        }
    }
    if ($dirty | is-not-empty) {
        print -e ($dirty | first 10 | str join "\n")
        if not $dry_run {
            let what = $"refused: the working tree has ($dirty | length) uncommitted changes"
            error make {msg: $"($what); commit \(dot sync\) or stash them first, a rollback never touches them"}
        }
        log-warn $"the working tree has ($dirty | length) uncommitted changes, a real rollback refuses"
    }
    let drive = drivers $sha $pin
    let installs = match [$full $admin $drive.nu] {
        [false _ _] => []
        [true false _] => [$drive.user]
        [true true true] => [$drive.root]
        _ => [$drive.root $drive.user]
    }
    let steps = [
        (if ($later | is-not-empty) { $"migration down ($later.id | reverse | str join ' ')" })
        $"git checkout --detach ($short)"
        (if $admin and not $drive.nu { "root copy --rollback" })
        (if ($stale | is-not-empty) { $"nix profile remove ($stale | str join ' ')" })
        ...($installs | each { str join " " })
        ($drive.apply | str join " ")
    ] | compact
    if $dry_run {
        log-info $"dry run, a clean tree would run: ($steps | str join ' -> ')"
        return
    }
    $later | reverse | each { migration-run $in down } | ignore
    ^git -C $REPO -c submodule.recurse=false checkout --quiet --detach $sha
    log-info $"checkout detached at ($short); return with: git switch ($BRANCH)"
    cd $REPO
    if $admin and not $drive.nu { copy-rollback }
    # install adds only what the profile lacks, so a stale one leaves first
    if ($stale | is-not-empty) { ^$NIX.0 ...($NIX | skip 1) profile remove ...$stale }
    with-env {LSCK0_SNAPSHOT: $pin, DOT_ROLLBACK: "1"} {
        let installs_ok = $installs | each { driver-run $in install } | all { $in }
        if $installs_ok {
            driver-run $drive.apply apply
        } else {
            log-warn "skipping apply: an install step failed, rollback is incomplete"
        }
    }
    log-info $"at ($short) \(($label)\); to return: git switch ($BRANCH) && dot apply --packages && dot apply"
}
