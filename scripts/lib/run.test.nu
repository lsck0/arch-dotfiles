#!/usr/bin/env -S nu --no-config-file
# The exit of each dot apply branch: its run sets DOT_SYSTEM_PENDING inside the guarded closure (or the --packages pass
# before it), and apply-finish, called in that closure, turns it into exit 3; a failure is exit 1 first. What
# failures-publish leaves of earlier FAILURES lines after a partial, a full and a clean run. The log tee keeps the
# command's exit code and session; a sync leaves root out only when every unprivileged reading says converged; a root
# entry's report becomes each step's code and FAILURES lines. Root's last report vouches only when its config step ended
# 0 and nothing else ended otherwise, an install pending only on packages the mirror's next build brings included; an
# unprivileged system plan names what is left for root, but not a secreted module's undoing of what it no longer
# declares. A pending module or packages note that waits on the mirror alone is no reason to enter root. A root copy from before
# `apply --run` is replaced through the argv it knows and then entered again; a dismissed pkexec prompt is no failure.
use state.nu [EXIT_PENDING EXIT_ABORTED]
use system.nu [ENTRY entry-takes-run]
use run.nu [failures-publish failures-system log-tee-argv system-due system-due-line upgrades-due awaited-arrived platform-edited stage-code stage-failures stages-due plan-due entry-enter entry-declined]
use std/assert

const REPO = path self ../..
const SHA = "0123456789abcdef0123456789abcdef01234567"
const RUN = "20261115T101010-abcd"
# the last generation whose entry knows no `apply --run`: what every machine installed before it still holds as root
const ENTRY_OLD_COMMIT = "d832fe855c3e5a2403d8483194ac9a762ebb315d"
const PKEXEC_DISMISSED = 126

const EXIT_FAILED = 1

const USER_LINE = "a/mod link/step: user broke"
const SYSTEM_LINE = "a/mod system/step: system broke"
const OTHER_LINE = "b/other link/step: other broke"
const PASSED = [{id: a/mod, ok: true, pending: null}]

def publish-cases []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-run-publish-XXXXXX
    let published = $dir | path join FAILURES.config
    let own = $dir | path join run.failures
    let earlier = [$USER_LINE $SYSTEM_LINE $OTHER_LINE]
    let cases = [
        [name full system_ran results new wants];
        ["partial keeps a passed module's system line" false false $PASSED [] [$SYSTEM_LINE $OTHER_LINE]]
        ["partial with the system layer clears the module" false true $PASSED [] [$OTHER_LINE]]
        ["partial adds a new failure" false false [{id: c/new, ok: false, pending: null}] ["c/new link/step: new"] [...$earlier "c/new link/step: new"]]
        ["full user-only keeps only system lines" true false $PASSED [] [$SYSTEM_LINE]]
        ["full clean run removes the file" true true $PASSED [] null]
    ]
    for c in $cases {
        $earlier | to text | save --force $published
        $c.new | each { $"($in)\n" } | str join | save --force $own
        let env_run = {DOT_FAILURES_OWNED: true, FAILURES_FILE: $own, DOT_FULL_RUN: $c.full, DOT_SYSTEM_RAN: $c.system_ran, DOT_RUN_ID: test}
        let ok = with-env $env_run { failures-publish $c.results $published }
        assert equal $ok ($c.new | is-empty) $"publish ($c.name): returned ($ok)"
        let got = if ($published | path exists) { open --raw $published | lines } else { null }
        assert equal $got $c.wants $"publish ($c.name): left ($got | to nuon)"
    }
    rm --recursive --force $dir
}

# sudo's tty ticket is keyed on the terminal and its session: the teed command must stay in the caller's session.
def tee-cases []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-run-tee-XXXXXX
    let log = $dir | path join out.log
    let argv = log-tee-argv $log [sh -c "echo to-stdout; echo to-stderr >&2; ps -o sid= -p $$; echo \"marked=$DOT_PTY_LOG\"; exit 7"]
    let run = ^$argv.0 ...($argv | skip 1) | complete
    let logged = open --raw $log
    rm --recursive --force $dir
    assert equal $run.exit_code 7 $"tee: exit ($run.exit_code), wants the command's 7"
    for want in [to-stdout to-stderr marked=1] {
        assert ($run.stdout | str contains $want) $"tee: the terminal side lacks ($want): ($run.stdout)"
        assert ($logged | str contains $want) $"tee: the log lacks ($want): ($logged)"
    }
    assert ($logged | lines | first | str contains "sh -c") $"tee: the log does not start with its command: ($logged)"
    let own = ^ps -o sid= -p $nu.pid | str trim
    assert ($run.stdout | lines | any { ($in | str trim) == $own }) $"tee: the command left session ($own): ($run.stdout)"
}

# A user layer failure is no reason to enter root; a system layer one and the install chain's are.
def failures-system-cases []: nothing -> nothing {
    let dir = mktemp --directory
    let config = $dir | path join FAILURES.config
    let install = $dir | path join FAILURES.install
    assert equal (failures-system $config $install) [] "failures-system: no files"
    "creating/obs link/eval: obs runs, close it\n" | save $config
    assert equal (failures-system $config $install) [] "failures-system: a user layer line"
    "creating/obs link/eval: obs runs, close it\na/mod system/step: broke\n" | save --force $config
    assert equal (failures-system $config $install) ["a/mod system/step: broke"] "failures-system: the system line of two"
    "pacman: x\n" | save $install
    assert equal (failures-system $config $install) ["a/mod system/step: broke" "pacman: x"] "failures-system: the install chain's"
    rm --recursive $dir
}

def due-cases []: nothing -> nothing {
    let settled = [config pending snapshot packages] | each { {level: ok, check: $in, text: fine} }
    let facts = {waiting: [], differs: false, entry: null}
    let cases = [
        [name checks facts wants];
        ["everything settled" $settled $facts []]
        ["the root copy differs" ($settled | update level {|r| if $r.check == config { "FAIL" } else { "ok" } }) $facts ["config: fine"]]
        ["a module waits" ($settled | update level {|r| if $r.check == pending { "note" } else { "ok" } }) $facts ["pending: fine"]]
        ["a check that did not report, as with no root copy yet" ($settled | where check != config) $facts ["config: not checked"]]
        ["a list that is not empty" $settled ($facts | update waiting [a/mod.key b/mod]) ["waiting: a/mod.key b/mod"]]
        ["a long list" $settled ($facts | update waiting (1..7 | into string)) ["waiting: 1 2 3 4 5 +2 more"]]
        ["a fact that holds" $settled ($facts | update differs true) ["differs"]]
        ["a text, as of an entry cut short after its unpack" $settled ($facts | update entry (stages-due null)) ["entry: left no report, it did not finish"]]
    ]
    for c in $cases {
        let got = system-due $c.checks $c.facts
        assert equal $got $c.wants $"due ($c.name): ($got | to nuon)"
    }
    let row = {|check, level, text| $settled | where check != $check | append {level: $level, check: $check, text: $text} }
    let awaiting = [
        [name checks awaited wants];
        ["packages the mirror's next build brings" (do $row packages note "not on the mirror yet: f") [] []]
        ["packages root installs" (do $row packages todo "dot apply --packages pending: g") [] ["packages: dot apply --packages pending: g"]]
        ["a module waiting on the mirror alone" (do $row pending note "fonts/fonts: packages missing: f") [fonts/fonts] []]
        ["a module waiting on packages root installs" (do $row pending note "a/mod: packages missing: g") [fonts/fonts] ["pending: a/mod: packages missing: g"]]
        ["one of two waiting on the mirror" ((do $row pending note "fonts/fonts: packages missing: f") | append {level: note, check: pending, text: "a/mod: waits on b (failed)"}) [fonts/fonts] ["pending: a/mod: waits on b (failed)"]]
    ]
    for c in $awaiting {
        let got = system-due $c.checks $facts $c.awaited
        assert equal $got $c.wants $"due ($c.name): ($got | to nuon)"
    }
    assert equal (upgrades-due 2) null "upgrades: checkupdates' 2 is not 'nothing to upgrade'"
    for code in [0 1 124 null] {
        assert ((upgrades-due $code) != null) $"upgrades: checkupdates ($code | to nuon) leaves root out"
    }
    # a wait on the mirror ends once a build carries the package, which no upgrade of an installed one need show
    assert equal (awaited-arrived [] null) null "arrived: nothing awaited"
    assert equal (awaited-arrived [f] [a b]) null "arrived: the mirror still lacks f"
    assert ((awaited-arrived [f g] [a g]) | str contains "g") "arrived: g on the mirror leaves root out"
    assert ((awaited-arrived [f] null) != null) "arrived: an unreadable database leaves root out"
    let dir = mktemp --directory --tmpdir dot-run-platform-XXXXXX
    let file = $dir | path join platform.options.nuon
    "{}\n" | save $file
    let at = ls $file | get 0.modified
    let edited = [
        [name since wants];
        ["no clean entry yet" null [$file]]
        ["edited after the last clean entry" ($at - 1sec) [$file]]
        ["entered since" ($at + 1sec) []]
    ]
    for c in $edited {
        let got = platform-edited [$file ($dir | path join absent.nuon)] $c.since
        assert equal $got $c.wants $"platform ($c.name): ($got | to nuon)"
    }
    rm --recursive --force $dir
}

def report-cases []: nothing -> nothing {
    let step = {|stage, code| {stage: $stage, code: $code, failures: []} }
    let cases = [
        [name report vouches];
        ["a sync that went through" {stages: [(do $step install 0) (do $step packages 0) (do $step config 0)]} true]
        ["a config entry that went through" {stages: [(do $step config 0)]} true]
        ["no report" null false]
        ["a report without stages" {stages: null} false]
        ["a report of no step" {stages: []} false]
        ["an install entry alone" {stages: [(do $step install 0) (do $step packages 0)]} false]
        ["a failed config" {stages: [(do $step config 1)]} false]
        ["a pending config" {stages: [(do $step config $EXIT_PENDING)]} false]
        ["a pending install" {stages: [(do $step install $EXIT_PENDING) (do $step packages 0) (do $step config 0)]} false]
        ["an aborted install" {stages: [(do $step install $EXIT_ABORTED)]} false]
    ]
    for c in $cases {
        let got = stages-due $c.report
        assert equal ($got == null) $c.vouches $"report ($c.name): ($got | to nuon)"
    }
    # awaited: root's ledger names packages only the mirror's next build brings, the one pending an install may end with
    let failed = {stage: install, code: $EXIT_PENDING, failures: ["x: broke"]}
    let awaited = [
        [name report vouches];
        ["an install pending on the mirror" {stages: [(do $step install $EXIT_PENDING) (do $step packages 0) (do $step config 0)]} true]
        ["an install pending with a failure" {stages: [$failed (do $step packages 0) (do $step config 0)]} false]
        ["a pending config" {stages: [(do $step install $EXIT_PENDING) (do $step config $EXIT_PENDING)]} false]
        ["a failed install" {stages: [(do $step install 1) (do $step config 0)]} false]
        ["an install pending, no config" {stages: [(do $step install $EXIT_PENDING)]} false]
        ["a report without failures" {stages: [{stage: install, code: $EXIT_PENDING} {stage: config, code: 0}]} true]
    ]
    for c in $awaited {
        let got = stages-due $c.report true
        assert equal ($got == null) $c.vouches $"report, awaited, ($c.name): ($got | to nuon)"
    }
}

def plan-cases []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-run-plan-XXXXXX
    let closed = $dir | path join closed
    mkdir $closed ($dir | path join open)
    ^chmod 000 $closed
    let act = {|kind, target, decl| {module: a/mod, kind: $kind, target: $target, reason: "", decl: $decl, before: null, after: null} }
    let planned = [
        {id: a/mod, error: null, actions: [
            (do $act skip /etc/same {})
            (do $act unreadable /etc/polkit-1/rules.d/x {})
            (do $act update /etc/changed {})
            (do $act drift /etc/edited {})
            (do $act step every-apply {})
            (do $act exec unseen {creates: ($closed | path join made)})
            (do $act exec missing {creates: ($dir | path join open made)})
            (do $act exec rekeyed {key: v2})
            (do $act disable old.service {})
        ]}
        {id: b/broken, error: "mod.nu does not parse", actions: []}
        {id: c/fresh, error: null, actions: []}
    ]
    let got = plan-due $planned
    # a secreted module: what it no longer declares says nothing, what it declares still does
    let secreted = [{id: s/mod, error: null, actions: [
        (do $act remove /etc/s/gone {kind: file})
        (do $act disable s.service {kind: unit, state: enabled, now: true})
        (do $act forget /etc/s/already {kind: file})
        (do $act disable declared.service {kind: unit, state: disabled})
        (do $act update /etc/s/changed {kind: file})
        (do $act drift /etc/s/edited {kind: file})
    ]}]
    let shown = plan-due $secreted [s/mod]
    let plain = plan-due $secreted
    ^chmod 700 $closed
    rm --recursive --force $dir
    assert equal $got ["b/broken: mod.nu does not parse" "a/mod: update /etc/changed" "a/mod: drift /etc/edited" "a/mod: exec missing" "a/mod: exec rekeyed" "a/mod: disable old.service"] $"plan: ($got | to nuon)"
    assert equal $shown ["s/mod: disable declared.service" "s/mod: update /etc/s/changed" "s/mod: drift /etc/s/edited"] $"plan, secreted: ($shown | to nuon)"
    assert equal ($plain | length) 6 $"plan, not secreted: ($plain | to nuon)"
}

# A stand-in root copy: its entry logs each call it accepts into <copy>/calls. The old one takes no --run and, as its
# `apply` does, replaces the copy (here: itself) before the stage; FIXTURE_KEEP leaves it, FIXTURE_EXIT is its code.
def copy-fixture [copy: path, old: bool]: nothing -> nothing {
    let lib = $copy | path join ($ENTRY | path dirname)
    mkdir $lib
    let head = "#!/usr/bin/env -S nu --no-config-file\nconst COPY = path self ../..\ndef main [] {}\n"
    let new = $head + 'def "main apply" [sha: string, stage: string, --run: string = "", --unattended, --force, --yes] {
    $"new ($stage) run=($run) unattended=($unattended) yes=($yes)\n" | save --append ($COPY | path join calls)
    exit ($env.FIXTURE_NEW_EXIT? | default 0 | into int)
}
'
    let old_entry = $head + 'def "main apply" [sha: string, stage: string, --unattended, --force, --yes] {
    if $stage not-in [install config] { error make {msg: $"apply: ($stage) is neither install nor config"} }
    $"old ($stage) unattended=($unattended) yes=($yes)\n" | save --append ($COPY | path join calls)
    if ($env.FIXTURE_KEEP? | is-empty) { open --raw ($COPY | path join new.nu) | save --force --raw ($COPY | path join ' + $ENTRY + ')}
    exit ($env.FIXTURE_EXIT? | default 0 | into int)
}
'
    $new | save --force ($copy | path join new.nu)
    (if $old { $old_entry } else { $new }) | save --force ($copy | path join $ENTRY)
    ^chmod 755 ($copy | path join $ENTRY)
    rm --force ($copy | path join calls)
}

def bridge-cases []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-run-bridge-XXXXXX
    let copy = $dir | path join repo
    let decline = $dir | path join decline
    $"#!/bin/sh\nexit ($PKEXEC_DISMISSED)\n" | save $decline
    ^chmod 755 $decline
    let flags = [--unattended=false --yes]
    let calls = {|| try { open --raw ($copy | path join calls) | lines } catch { [] } }

    # what this guards against: nu rejects the unknown flag before the old entry's body, so nothing is ever unpacked
    copy-fixture $copy true
    let direct = ^env ($copy | path join $ENTRY) apply $SHA install --run $RUN ...$flags | complete
    assert ($direct.exit_code != 0 and (do $calls) == []) $"bridge: the old fixture took --run: ($direct | to nuon)"

    let cases = [
        [name old stage runner vars code wants replaced];
        ["a sync into an old copy" true sync env {} 0 ["old install unattended=false yes=true" $"new sync run=($RUN) unattended=false yes=true"] true]
        ["an apply into an old copy" true config env {} 0 ["old config unattended=false yes=true" $"new config run=($RUN) unattended=false yes=true"] true]
        ["a failed bridge stage still enters" true sync env {FIXTURE_EXIT: 1} 0 ["old install unattended=false yes=true" $"new sync run=($RUN) unattended=false yes=true"] true]
        ["an aborted bridge is the result" true sync env {FIXTURE_EXIT: $EXIT_ABORTED} $EXIT_ABORTED ["old install unattended=false yes=true"] true]
        ["an interrupted bridge is the result" true sync env {FIXTURE_EXIT: 130} 130 ["old install unattended=false yes=true"] true]
        ["a bridge that unpacked nothing fails" true sync env {FIXTURE_KEEP: 1} 1 ["old install unattended=false yes=true"] false]
        ["a dismissed prompt at the bridge" true sync $decline {} $PKEXEC_DISMISSED [] false]
        ["a current copy is entered once" false sync env {} 0 [$"new sync run=($RUN) unattended=false yes=true"] true]
        ["a current copy's own code" false config env {FIXTURE_NEW_EXIT: $EXIT_PENDING} $EXIT_PENDING [$"new config run=($RUN) unattended=false yes=true"] true]
    ]
    for c in $cases {
        copy-fixture $copy $c.old
        let code = with-env ($c.vars | merge {DOT_RUN_FILE: "", DOT_NO_JOURNAL: 1}) { entry-enter $c.runner $copy $SHA $c.stage $RUN $flags 0x[00] }
        assert equal $code $c.code $"bridge ($c.name): exit ($code)"
        assert equal (do $calls) $c.wants $"bridge ($c.name): the entries called"
        assert equal (entry-takes-run $copy) $c.replaced $"bridge ($c.name): the copy afterwards"
    }
    rm --recursive --force $dir
}

# The entry every machine holds as root until its first run of this protocol, from git: it rejects the new argv before
# its body and takes the bridge's as far as its root check; its imports come with it. Skipped where the object store
# lacks that commit.
def bridge-real-entry []: nothing -> nothing {
    let has = with-env {GIT_NO_LAZY_FETCH: 1} { ^git -C $REPO cat-file -e $"($ENTRY_OLD_COMMIT):($ENTRY)" | complete }
    if $has.exit_code != 0 or (is-admin) { return }
    let dir = mktemp --directory --tmpdir dot-run-old-entry-XXXXXX
    with-env {GIT_NO_LAZY_FETCH: 1} { ^git -C $REPO archive $ENTRY_OLD_COMMIT ($ENTRY | path dirname) ":(glob)configs/**/*.nu" ":(glob)platforms/*.nu" | ^tar -x -C $dir -f - }
    let entry = $dir | path join $ENTRY
    let current = ^$nu.current-exe --no-config-file $entry apply $SHA sync --run $RUN --unattended=false | complete
    let bridged = ^$nu.current-exe --no-config-file $entry apply $SHA install --unattended=false --yes | complete
    let takes = entry-takes-run $dir
    rm --recursive --force $dir
    assert (not $takes) "old entry: read as taking --run"
    assert ($current.exit_code != 0 and ($current.stderr | str contains "--run")) $"old entry: took this protocol's argv: ($current.stderr)"
    assert ($bridged.stderr | str contains "run as root") $"old entry: the bridge's argv did not reach its body: ($bridged.stderr)"
    assert (entry-takes-run $REPO) "this checkout's entry is not read as taking --run: the bridge would run on every entry"
}

def declined-cases []: nothing -> nothing {
    let silent = {|code| {code: $code, run: null, stages: []} }
    let cases = [
        [name ran runner wants];
        ["a dismissed pkexec prompt" (do $silent $PKEXEC_DISMISSED) pkexec true]
        ["pkexec not authorized" (do $silent 127) pkexec true]
        ["the same code from sudo" (do $silent $PKEXEC_DISMISSED) sudo false]
        ["an entry that failed without a report" (do $silent 1) pkexec false]
        ["a step root reported with that code" {code: 1, run: $RUN, stages: [{stage: config, code: $PKEXEC_DISMISSED, failures: []}]} pkexec false]
    ]
    for c in $cases {
        assert equal (entry-declined $c.ran $c.runner) $c.wants $"declined ($c.name)"
    }
}

def stage-cases []: nothing -> nothing {
    let reported = {code: 1, run: "20261115T204044-abcd", stages: [
        {stage: install, code: $EXIT_PENDING, failures: []}
        {stage: packages, code: 0, failures: []}
        {stage: config, code: 1, failures: ["a/mod system/step: broke" "ledger: disabling dropped units: x"]}
    ]}
    assert equal (stage-code $reported install) $EXIT_PENDING "stage: install's own code"
    assert equal (stage-code $reported config) 1 "stage: config's own code"
    assert equal (stage-failures $reported config sudo) ["a/mod system/step: broke" "system layer ledger: disabling dropped units: x"] "stage: root's lines, the layer named"
    let aborted = {code: $EXIT_ABORTED, run: "20261115T204044-abcd", stages: [{stage: install, code: $EXIT_ABORTED, failures: ["pacman: x"]}]}
    assert equal (stage-code $aborted config) null "stage: a step the entry never reached has no code"
    let silent = {code: 1, run: null, stages: []}
    assert equal (stage-code $silent config) 1 "stage: no report, the entry's code"
    let line = stage-failures $silent config sudo | first
    assert (($line | str contains "exited 1, root recorded no failure") and ($line | str contains "/var/lib/dotfiles/runs")) $"stage: the silent line: ($line)"
    let known = stage-failures {code: 1, run: "20261115T204044-abcd", stages: [{stage: config, code: 1, failures: []}]} config sudo | first
    assert ($known | str contains "runs/20261115T204044-abcd.jsonl") $"stage: the line does not name root's run file: ($known)"
}

# The line before the root entry: the first reason's first line, then how many more.
def due-line-cases []: nothing -> nothing {
    let cases = [
        [name due wants];
        ["one" ["the system plan: base/ssh: update /etc/ssh/sshd_config"] "system layer: entering root for the system plan: base/ssh: update /etc/ssh/sshd_config"]
        ["several" ["package upgrades are available" "migrations pending: 0042-x" "config: x"] "system layer: entering root for package upgrades are available, 2 more"]
        ["a multi-line reason" ["packages: a\nb"] "system layer: entering root for packages: a"]
    ]
    for c in $cases {
        let got = system-due-line $c.due
        assert equal $got $c.wants $"due line ($c.name)"
    }
}

def main [] {
    due-line-cases
    publish-cases
    tee-cases
    failures-system-cases
    due-cases
    report-cases
    plan-cases
    bridge-cases
    bridge-real-entry
    declined-cases
    stage-cases
    let state = mktemp --directory --tmpdir dot-run-test-XXXXXX
    let src = "use cli.nu [guarded]; use run.nu [apply-finish]
def --env run-held [] { $env.DOT_SYSTEM_PENDING = true; [{id: t/held, ok: true, pending: 'packages missing: x', outcomes: [], log: ''}] }
def --env run-clean [] { [{id: t/clean, ok: true, pending: null, outcomes: [], log: ''}] }
def --env run-failed [] { $env.DOT_SYSTEM_PENDING = true; [{id: t/failed, ok: false, pending: null, outcomes: [], log: ''}] }
"
    # each branch's shape in dot.nu's main apply, the run standing in for link-run or apply-run
    let cases = [
        [name call wants];
        ["a module held" "guarded apply --read-only { run-held | apply-finish $in }" $EXIT_PENDING]
        ["nothing held" "guarded apply --read-only { run-clean | apply-finish $in }" 0]
        ["after --packages left something pending" "$env.DOT_SYSTEM_PENDING = true; guarded apply --read-only { run-clean | apply-finish $in }" $EXIT_PENDING]
        ["a failure wins over pending" "guarded apply --read-only { run-failed | apply-finish $in }" $EXIT_FAILED]
    ]
    for c in $cases {
        let run = with-env {XDG_STATE_HOME: $state, FAILURES_FILE: null} { ^$nu.current-exe --no-config-file -I ($env.FILE_PWD) -c $"($src)($c.call)" | complete }
        if $run.exit_code != $c.wants {
            rm --recursive --force $state
            error make {msg: $"($c.name): exit ($run.exit_code), wants ($c.wants)\n($run.stdout)($run.stderr)"}
        }
    }
    rm --recursive --force $state
}
