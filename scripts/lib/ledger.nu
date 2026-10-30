# dot's ledger: one '<kind> <name>' line per unit, package, migration or marker it recorded.

use log.nu *
use state.nu [state-dir save-atomic]
use preserve.nu [tty-confirm]
use converge.nu [unit-states]

export const PACKAGES_DENY = '^(base|base-devel|linux.*|.*-firmware|.*-ucode|binutils|sbctl|cryptsetup|btrfs-progs|mkinitcpio|systemd.*|networkmanager|sudo|pacman|git|gnupg|yay|nix|nushell|libfido2|openssh|age|age-plugin-yubikey|git-crypt|pcsclite|zsh)$'
const UNIT_NAME = '[A-Za-z0-9][A-Za-z0-9:_.-]*(@[A-Za-z0-9:_.-]*)?\.(service|socket|timer|path|mount|automount|target)'

export def ledger-file []: nothing -> path {
    state-dir | path join ledger
}

# Sorted.
export def ledger-get [kind: string]: nothing -> list<string> {
    let file = ledger-file
    if not ($file | path exists) { return [] }
    open --raw $file | lines | where ($it | str starts-with $"($kind) ") | each { str substring (($kind | str length) + 1).. } | sort
}

export def ledger-set [kind: string, names: list<string>]: nothing -> nothing {
    let file = ledger-file
    mkdir ($file | path dirname)
    let kept = if ($file | path exists) { open --raw $file | lines | where not ($it | str starts-with $"($kind) ") } else { [] }
    $kept | append ($names | where $it != "" | each { $"($kind) ($in)" }) | uniq | sort | str join "\n" | $"($in)\n" | save-atomic $file
}

# Recorded names installed but no longer declared (dropped), and installed names neither recorded nor declared
# (by_hand); keep spares a name from both.
export def ledger-diff [owned: list<string>, declared: list<string>, installed: list<string>, keep: list<string> = []]: nothing -> record {
    {
        dropped: ($owned | where {|n| $n in $installed and $n not-in $declared and $n not-in $keep })
        by_hand: ($installed | where {|n| $n not-in $owned and $n not-in $declared and $n not-in $keep })
    }
}

# Removes, after a yes (yes skips it), what the ledger records under kind and no module declares any more. What was
# installed by hand and is neither declared nor kept is only listed; --offer-by-hand asks for it too, even with yes.
# remove gets the names.
export def ledger-remove [kind: string, declared: list<string>, installed: list<string>, keep: list<string>, yes: bool, remove: closure, --offer-by-hand]: nothing -> nothing {
    let diff = ledger-diff (ledger-get $kind) $declared $installed $keep
    let dropped = if ($diff.dropped | is-not-empty) and ($yes or (tty-confirm $"ledger: remove ($kind) ($diff.dropped | str join ' ')?")) { $diff.dropped } else { [] }
    let by_hand = if ($diff.by_hand | is-empty) { [] } else if not $offer_by_hand {
        log-info $"($kind) installed by hand, not managed: ($diff.by_hand | str join ' ')"
        []
    } else {
        print $"($kind), installed by hand, declared by no module: ($diff.by_hand | str join ' ')"
        if (tty-confirm $"remove these ($diff.by_hand | length)? \(($kind)_keep in the platform spares them\)") { $diff.by_hand } else { [] }
    }
    let removing = $dropped ++ $by_hand
    let removed = ($removing | is-not-empty) and (try { do $remove $removing; true } catch {|e| fail $"ledger: removing ($kind) ($removing | str join ' '): ($e.msg)"; false })
    ledger-set $kind ($declared | where $it in $installed | append ($diff.dropped | where {|n| not $removed or $n not-in $removing }))
}

# Dropped units are disabled after a yes; by_hand lists units enabled outside dot.
export def ledger-units [repo: path, dirs: list<path>, scope: string, --plan]: nothing -> record {
    let paths = $dirs | append ($repo | path join scripts) | where ($it | path exists)
    let declared = ^grep -rhoIE $UNIT_NAME --exclude=*.log -- ...$paths | lines | uniq
    let owned_before = ledger-get unit | where ($it | str starts-with $"($scope) ") | each { str substring (($scope | str length) + 1).. }
    let names = $declared | append $owned_before | uniq | sort
    let states = unit-states $scope $names
    if ($states | length) != ($names | length) {
        error make {msg: $"systemctl --($scope) is-enabled answered ($states | length) of ($names | length) units"}
    }
    let enabled = $names | zip $states | where $it.1 == "enabled" | each { $in.0 }
    let dropped = $enabled | where $it not-in $declared
    let disable = not $plan and ($dropped | is-not-empty) and (tty-confirm $"ledger: disable ($dropped | str join ' ')?")
    if $disable {
        ^systemctl $"--($scope)" disable --now ...$dropped
    }
    let owned = $enabled | where $it in $declared | append (if $disable { [] } else { $dropped })
    if not $plan {
        ledger-set unit ($owned | each { $"($scope) ($in)" } | append (ledger-get unit | where not ($it | str starts-with $"($scope) ")))
    }
    let by_hand = ^systemctl $"--($scope)" list-unit-files --state=enabled --no-legend | lines
        | parse --regex '^(?<unit>\S+)\s+(?<state>\S+)\s+(?<preset>\S+)' | where preset != enabled and unit not-in $owned | get unit
    {owned: $owned, dropped: (if $disable { [] } else { $dropped }), by_hand: $by_hand}
}

# Installed packages the declared names and groups resolve to.
def packages-resolve [declared: list<string>]: nothing -> list<string> {
    ^pacman -Qq ...$declared | complete | get stdout | lines
        | append (^pacman -Qqg ...$declared | complete | get stdout | lines | each { split row " " | last })
        | uniq
}

# Explicitly installed packages that no module declares, keep lists or PACKAGES_DENY spares.
export def packages-convergence [declared: list<string>, keep: list<string>]: nothing -> record {
    let resolved = packages-resolve $declared
    let explicit = ^pacman -Qqe | lines
    let extra = $explicit | where $it not-in $resolved and $it not-in $keep and not ($it =~ $PACKAGES_DENY)
    {declared: ($resolved | length), explicit: ($explicit | length), remove: $extra}
}

# Removes, after a yes (yes skips the question), recorded packages no module declares; what another package still
# needs stays as a dependency.
export def ledger-packages [declared: list<string>, yes: bool]: nothing -> nothing {
    let resolved = packages-resolve $declared | sort
    if ($resolved | is-empty) { error make {msg: $"none of the ($declared | length) declared packages is installed, refusing"} }
    let installed = ^pacman -Qq | lines
    let dropped = (ledger-diff (ledger-get pkg) $resolved $installed).dropped | where not ($it =~ $PACKAGES_DENY)
    let removing = ($dropped | is-not-empty) and ($yes or (tty-confirm $"ledger: remove ($dropped | str join ' ')?"))
    if $removing {
        ^pacman -D --asexplicit ...$resolved | ignore
        ^pacman -D --asdeps ...$dropped | ignore
        let orphans = ^pacman -Qdttq | complete | get stdout | lines | where $it in $dropped
        if ($orphans | is-not-empty) { ^pacman -Rns --noconfirm ...$orphans }
    }
    ledger-set pkg ($resolved ++ (if $removing { [] } else { $dropped }))
    let by_hand = ^pacman -Qqe | lines | where $it not-in (ledger-get pkg)
    if ($by_hand | is-not-empty) { log-info $"installed by hand, not managed: ($by_hand | str join ' ')" }
}
