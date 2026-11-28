#!/usr/bin/env -S nu --no-config-file
# Third-party sources are pinned (l-dotfiles-add-package, Supply chain). A source that floats fails, outside EXCEPTIONS:
# the floating sources this lint tracks (the skill lists only those it cannot see) and lines pinned another way.
# A pin's age is its upstream date, read offline from where it is written down: a *_FROZEN, EXCLUDE_NEWER or
# _exclude_newer cutoff, a uv.lock's upload times, or an ISO date in a comment on the pin's own line or in the comment
# lines directly above it (`# v1.0.3, 2026-09-11`). A pin older than MAX_AGE, a pin with no date and an exception that
# matches nothing any more are warnings on stderr, which dot test lint shows as notes; they never fail.
use std/assert

const REPO = path self ../..
const MAX_AGE = 90day
# one walk of configs: module code, the browser policies and the lock that records dates (package-lock.json,
# lazy-lock.json and constraints.txt record none)
const SOURCES = [
    "configs/**/{*.nu,*.sh,policies.json,policy.json,uv.lock}" "mirror/pkgbuilds/*/PKGBUILD" "scripts/lib/run.nu"
    "scripts/lib/module.nu"
]
const LOCKS = [uv.lock]
# the private submodule: its modules are the owner's, its data is not source
const SKIPPED = ["**/configs/secrets/**" "**/node_modules/**" "**/*.test.nu"]

# unless: what on the line or the two after it makes the match a pinned install
const FLOATING = [
    [rule pattern unless why];
    [npx '\bnpx\b' '' "npx resolves the package's dependencies at run time: mcp-npm on a committed package-lock.json"]
    [python '(?:^|[^\w-])uvx\b|\b(?:uv tool|uv pip|pip) install\b' '--exclude-newer|--constraints|--no-index' "python dependencies with no cutoff date, constraints file or local index"]
    [npm '\bnpm (?:install|i)\b' '' "npm install resolves dependencies as it runs: npm ci on a committed lock"]
    [cargo '\bcargo install\b' '--locked' "cargo install without --locked resolves dependencies as it runs"]
    [go '\bgo install\b' '' "go install fetches whatever the version query names today: an own pkgbuild at a commit"]
    [rustup '\brustup (?:-{1,2}[\w-]+ )*(?:update|default stable|toolchain install (?:stable|beta|nightly))\b' '' "a rustup channel is whatever is current that day"]
    [clone '\bgit clone\b' '' "a clone lands on the default branch: fetch-git at a commit"]
    [latest 'downloads/latest/|releases/latest\b|@latest\b' '' "a url or version that names the latest release"]
    [extension '--install-extension\b|clients2\.google\.com/service/update2' '' "a store extension at its current version"]
    [pipe '\b(?:curl|wget)\b[^|]*\|\s*(?:sudo\s+)?(?:ba|z)?sh\b' '' "an installer piped into a shell: fetch-file with its sha256"]
    [git-source 'git\+https?://' '#commit=' "a pkgbuild git source without #commit="]
]
const EXCEPTIONS = [
    [file rule why];
    [configs/programming/kubernetes/mod.nu npx "kubernetes-mcp-server, no lockfile yet"]
    [configs/programming/caveman/mod.nu npx "the skills cli, no lockfile yet"]
    [configs/programming/vscode/mod.nu extension "the vim extension, latest"]
    [configs/desktop/firefox/config/policies.json latest "store extensions, latest"]
    [configs/desktop/chromium/config/policy.json extension "store extensions, latest"]
    [configs/programming/cargo/mod.nu rustup "rustup toolchains track their channel"]
    [configs/programming/formatting/mod.nu rustup "rustfmt's nightly"]
    [scripts/lib/run.nu rustup "the default stable toolchain"]
    [mirror/pkgbuilds/lean-tui/PKGBUILD rustup "the nightly current at build time"]
    [mirror/pkgbuilds/bloodyad/PKGBUILD python "badldap and kerbad with their dependencies, no hashes"]
    [mirror/pkgbuilds/bruno-cli/PKGBUILD npm "the registry tarball's dependencies"]
    [mirror/pkgbuilds/kulala-fmt/PKGBUILD npm "the registry tarball's dependencies"]
    # pinned another way
    [mirror/pkgbuilds/hexchat/PKGBUILD git-source "a tag under a makepkg checksum: a moved tag fails the build"]
    [configs/desktop/hyprland/scripts/plugins.nu clone "cloned, then checked out at the pinned commit"]
    [configs/core/ntfy/mod.nu clone "the homelab repo, the owner's own"]
    [configs/core/git/config/aliases.nu clone "the git wrapper: it clones what its caller names"]
]

const HEX_PIN = '\b(?:[0-9a-f]{40}|[0-9a-f]{64})\b'
const HEX_ZERO = '\b0{40,}\b'
const CUTOFF = '(?:FROZEN|EXCLUDE_NEWER|_exclude_newer) ?= ?"(?<date>\d{4}-\d{2}-\d{2})"'
const COMMENT_DATE = '(?:^|\s)#\s.*?\b(?<date>\d{4}-\d{2}-\d{2})\b'
const UPLOAD_TIME = 'upload-time = "(?<date>\d{4}-\d{2}-\d{2})'
const HEADER_LINES_MAX = 3

def comment [line: string]: nothing -> bool { $line | str trim --left | str starts-with "#" }

def line-date [line: string]: nothing -> any { $line | parse --regex $COMMENT_DATE | get --optional 0.date }

# The lines of text a FLOATING rule flags.
def floating-find [text: string]: nothing -> table<n: int, rule: string> {
    let any = $FLOATING.pattern | str join "|"
    if $text !~ $any { return [] }
    let lines = $text | lines
    $lines | enumerate | where $it.item =~ $any and not (comment $it.item) | each {|l|
        let window = $lines | slice $l.index..($l.index + 2) | str join " "
        $FLOATING | where {|r| $l.item =~ $r.pattern and ($r.unless == "" or $window !~ $r.unless) }
        | each {|r| {n: ($l.index + 1), rule: $r.rule} }
    } | flatten
}

# The pins text holds, each with its date or null: a cutoff line, a line with a commit or sha256 that carries its own
# date, and each run of adjacent such lines without one, dated by the comment lines above the run.
def pins-find [text: string]: nothing -> table<n: int, date: any> {
    let lines = $text | lines
    let cutoffs = $lines | enumerate | where $it.item =~ $CUTOFF | each {|l|
        let date = $l.item | parse --regex $CUTOFF | get --optional 0.date
        if $date != null { {n: ($l.index + 1), date: $date} }
    } | compact
    if $text !~ $HEX_PIN { return $cutoffs }
    let hex = $lines | each {|l| $l =~ $HEX_PIN and $l !~ $HEX_ZERO and not (comment $l) }
    let runs = $hex | enumerate | where item | each {|l|
        let own = line-date ($lines | get $l.index)
        if $own != null { return {start: $l.index, n: ($l.index + 1), date: $own, own: true} }
        mut start = $l.index
        while $start > 0 and ($hex | get ($start - 1)) and (line-date ($lines | get ($start - 1))) == null { $start -= 1 }
        let header = $lines | first $start | last $HEADER_LINES_MAX | reverse | take while {|h| comment $h }
        {start: $start, n: ($start + 1), date: ($header | each {|h| line-date $h } | compact | get --optional 0), own: false}
    }
    let owned = $runs | where own
    let shared = $runs | where not own | uniq-by start
    $cutoffs ++ ($owned ++ $shared | select n date) | sort-by n
}

def cases-check [] {
    let floating = [
        [name text wants];
        ["npx" "exec [npx -y pkg@1.0.0]" [npx]]
        ["npx in a comment" "# npx floats" []]
        ["npm ci" "npm ci --prefix $dir" []]
        ["npm install" "    npm install -g ./pkg.tgz" [npm]]
        ["uv tool with a cutoff" "^uv tool install --exclude-newer $FROZEN $pkg" []]
        ["uv pip with the cutoff a line on" "(^uv pip install --python $venv\n    --exclude-newer $DATE $pkg)" []]
        ["bare pip" "python -m pip install requests" [python]]
        ["nightly" "rustup toolchain install nightly --profile minimal" [rustup]]
        ["a pinned channel" "rustup toolchain install $channel" []]
        ["update behind a global flag" "^rustup --quiet update" [rustup]]
        ["latest xpi" '"install_url": "https://addons.mozilla.org/firefox/downloads/latest/x/latest.xpi"' [latest]]
        ["piped installer" "curl -fsSL https://example.org/install.sh | sh" [pipe]]
        ["git source at a commit" 'source=("git+https://example.org/x.git#commit=0123")' []]
        ["git source at a branch" 'source=("git+https://example.org/x.git#branch=main")' [git-source]]
    ]
    for c in $floating {
        assert equal (floating-find $c.text | get rule) $c.wants $c.name
    }
    let commit = "0123456789abcdef0123456789abcdef01234567"
    let pins = [
        [name text wants];
        ["cutoff" 'const MCP_FROZEN = "2026-10-14"' [[n date]; [1 "2026-10-14"]]]
        ["date on the line" $"const COMMIT = \"($commit)\" # 4.1.3, 2025-01-29" [[n date]; [1 "2025-01-29"]]]
        ["date above" $"# v1.0.3, 2026-09-11; bump with constraints.txt\nconst COMMIT = \"($commit)\"" [[n date]; [2 "2026-09-11"]]]
        ["no date" $"const COMMIT = \"($commit)\"" [[n date]; [1 null]]]
        ["a run shares the date above it" $"# 2026-10-28\n    commit: ($commit)\n    sha256: ($commit)($commit | str substring 0..<24)" [[n date]; [2 "2026-10-28"]]]
        ["rows with their own" $"[a ($commit)] # 2026-01-01\n[b ($commit)] # 2026-02-02\n[c ($commit)]" [[n date]; [1 "2026-01-01"] [2 "2026-02-02"] [3 null]]]
        ["a blank line ends the reach" $"# 2026-10-28\n\nconst COMMIT = \"($commit)\"" [[n date]; [3 null]]]
        ["zeros are no pin" $"const INITIAL = \"('' | fill --character 0 --width 64)\"" []]
    ]
    for c in $pins {
        assert equal (pins-find $c.text) $c.wants $c.name
    }
}

def files []: nothing -> table<file: string, text: string, lock: bool> {
    $SOURCES | each {|g| glob ($REPO | path join $g) --exclude $SKIPPED } | flatten | sort
    | each {|f| {file: ($f | path relative-to $REPO), text: (open --raw $f | decode utf-8), lock: (($f | path basename) in $LOCKS)} }
}

def warn [msg: string]: nothing -> nothing { print --stderr $"pins.test: warn: ($msg)" }

def main [] {
    cases-check
    let files = files
    let sources = $files | where not lock
    let floating = $sources | each {|s| floating-find $s.text | insert file $s.file } | flatten
    let stale = $EXCEPTIONS | where {|e| ($floating | where file == $e.file and rule == $e.rule | is-empty) }
    for e in $stale { warn $"($e.file) no longer trips ($e.rule): drop its exception" }
    let failures = $floating | where {|f| ($EXCEPTIONS | where file == $f.file and rule == $f.rule | is-empty) } | each {|f|
        $"($f.file):($f.n): ($FLOATING | where rule == $f.rule | get 0.why)"
    }

    let locks = $files | where lock | each {|l| {file: $l.file, n: 1, date: ($l.text | parse --regex $UPLOAD_TIME | get date | sort | last 1 | get --optional 0)} }
    let pins = ($sources | each {|s| pins-find $s.text | insert file $s.file } | flatten) ++ $locks
    let today = date now
    for p in ($pins | where date != null | sort-by date) {
        let age = $today - ($p.date | into datetime)
        if $age > $MAX_AGE { warn $"($p.file):($p.n): pinned ($p.date), ($age / 1day | math floor) days old" }
    }
    let undated = $pins | where date == null
    if ($undated | is-not-empty) {
        let where = $undated | group-by file --to-table | each {|g| $"($g.file):($g.items.n | str join ',')" } | str join " "
        warn $"($undated | length) pins carry no date \(an ISO date in a comment on the pin's line or above it\): ($where)"
    }

    if ($failures | is-not-empty) {
        error make {msg: $"pins.test: a third-party source with no pin \(pin it, or list it in the package skill and in EXCEPTIONS\):\n($failures | str join "\n")"}
    }
}
