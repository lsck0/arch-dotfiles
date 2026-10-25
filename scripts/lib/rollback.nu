# `dot rollback`: check out an older generation of master and converge to it, undoing later migrations first.
# Packages stay as installed; the config layer goes back.

use log.nu [log-info log-warn]
use state.nu [SYSTEM_REPO]
use system.nu [ENTRY]
use ledger.nu [ledger-get]
use migrate.nu [migrations-list migration-run]

const REPO = path self ../..
const BRANCH = "master"
const FLOOR_FILES = [scripts/lib/system-apply.sh scripts/lib/system-apply.nu]

def --wrapped git-out [...args: string]: nothing -> string { ^git -C $REPO ...$args | str trim }

def --wrapped git-ok [...args: string]: nothing -> bool { (do { ^git -C $REPO ...$args } | complete).exit_code == 0 }

def describe-commit [rev: string]: nothing -> string { git-out log -1 "--format=%s, %ci" $rev }

# The commit of a generation number or revision, refused unless on master and new enough to have the root copy.
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

# The target's own apply: a generation from before system-apply.nu applied with config.sh and the root copy's
# bash rollback.
def drivers [sha: string]: nothing -> record {
    if (git-ok cat-file -e $"($sha):scripts/lib/system-apply.nu") {
        {apply: [nu --no-config-file scripts/dot.nu apply], nu: true}
    } else {
        {apply: [./config.sh], nu: false}
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

export def rollback-run [target: string, --dry-run]: nothing -> nothing {
    if (is-admin) { error make {msg: "run as the admin, not root; the root half goes through sudo"} }
    if ($env.DIRENV_DIR? | is-not-empty) { error make {msg: "run outside a direnv directory"} }
    let sha = rollback-resolve $target
    let short = $sha | str substring 0..11
    let newer = migrations-list $REPO | where {|m| not (git-ok cat-file -e $"($sha):($m.file | path relative-to $REPO)") }
    # user ones from this ledger; system ones root checks against its own ledger (migrate --down)
    let later = $newer | where layer == user and id in (ledger-get migration)
    let later_system = $newer | where layer == system
    let stuck = $later ++ $later_system | where not reversible
    if ($stuck | is-not-empty) { error make {msg: $"($target) predates migration ($stuck.id | str join ', '), which has no down"} }
    let label = describe-commit $sha
    let admin = ^id -nG | split row " " | any { $in == wheel }
    let dirty = git-out status --porcelain --ignore-submodules=all | lines
    log-info $"target ($short) \(($label)\)"
    log-info $"from   (git-out rev-parse HEAD | str substring 0..11) \((describe-commit HEAD)\)"
    log-info $"config layer: (git-out diff --shortstat $sha HEAD -- . ':!configs/secrets')"
    if $admin {
        let source = try { open --raw ($SYSTEM_REPO | path join .source) | str trim } catch { "none" }
        log-info $"root copy ($SYSTEM_REPO) at ($source), stepped back to ($short)"
    } else {
        log-info "not in wheel: the user layer only"
    }
    if ($dirty | is-not-empty) {
        print -e ($dirty | first 10 | str join "\n")
        if not $dry_run {
            let what = $"refused: the working tree has ($dirty | length) uncommitted changes"
            error make {msg: $"($what); commit \(dot sync\) or stash them first, a rollback never touches them"}
        }
        log-warn $"the working tree has ($dirty | length) uncommitted changes, a real rollback refuses"
    }
    let drive = drivers $sha
    let steps = [
        (if ($later | is-not-empty) { $"migration down ($later.id | reverse | str join ' ')" })
        (if $admin and ($later_system | is-not-empty) { $"root migration down ($later_system.id | reverse | str join ' ')" })
        $"git checkout --detach ($short)"
        (if $admin and not $drive.nu { "root copy --rollback" })
        ($drive.apply | str join " ")
    ] | compact
    if $dry_run {
        log-info $"dry run, a clean tree would run: ($steps | str join ' -> ')"
        return
    }
    $later | reverse | each { migration-run $in down } | ignore
    if $admin and ($later_system | is-not-empty) {
        ^sudo ($SYSTEM_REPO | path join $ENTRY) migrate --down ...$later_system.id
    }
    ^git -C $REPO -c submodule.recurse=false checkout --quiet --detach $sha
    log-info $"checkout detached at ($short); return with: git switch ($BRANCH)"
    cd $REPO
    if $admin and not $drive.nu { copy-rollback }
    with-env {DOT_ROLLBACK: "1"} { driver-run $drive.apply apply | ignore }
    log-info $"at ($short) \(($label)\); to return: git switch ($BRANCH) && dot apply"
}
