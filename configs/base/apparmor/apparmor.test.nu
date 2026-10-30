#!/usr/bin/env -S nu --no-config-file

const HERE = path self | path dirname
const MARKER = "# managed by arch-dotfiles/apparmor"
const OWN_SUFFIX = ".dotfiles"
const OVERRIDES = [firefox thunderbird libreoffice]
const ENFORCED = [
    firefox chromium qutebrowser lynx cha thunderbird discord signal-desktop telegram-desktop element-desktop hexchat
    zapzap protonmail wireshark spotify mpv zathura sioyek okular bookokrat libreoffice onlyoffice feh nsxiv obsidian
    zotero localsend-app qbittorrent ouch 7z unrar unzip magick pdftoppm ffmpeg ffprobe handbrake
    blender-mcp obs-mcp child-open child-open-any child-open-browsers child-open-strict
]
# rules other modules rely on: the discord voice plugin claims its command file by renaming it to .reading
const REQUIRED_RULES = {
    discord: ["owner @{run}/user/@{uid}/quickshell-discord-cmd{,.reading} rw,"]
}

def basenames [dir: string]: nothing -> list<string> {
    ls $dir | get name | path basename
}

def rows-check [rows: table]: nothing -> list<string> {
    let own = basenames profiles
    let malformed = $rows | each {|r|
        let mode = $r.mode | split row "," | first
        [
            (if $r.extra != "" or $mode not-in [enforce complain] {
                $"profiles.conf: bad row '($r.name) ($r.mode) ($r.extra)'"
            })
            (if ($r.mode | str contains ",") and $r.name in $own {
                $"profiles/($r.name): flags belong in its header, not profiles.conf"
            })
        ]
    } | flatten | compact
    let twice = $rows | get name | uniq --repeated
    let loose = $ENFORCED
        | where {|n| ($rows | where name == $n | get mode | each { split row "," | first }) != [enforce] }
    let listed_twice = if ($twice | is-empty) { [] } else { [$"profiles.conf lists twice: ($twice | str join ' ')"] }
    $malformed ++ $listed_twice ++ ($loose | each { $"($in) is not enforced in profiles.conf" })
}

def own-check [rows: table]: nothing -> list<string> {
    let profiles = basenames profiles | each {|name|
        let lines = open --raw ($"profiles/($name)") | lines
        [
            (if $name not-in $rows.name { $"profiles/($name) is not in profiles.conf" })
            (if ($lines | first) != $MARKER { $"profiles/($name) lacks the marker line" })
            # any attachment: 7z spells its paths out, apparmor 4.1.8 never attaches its @{bin}/@{lib} expansion
            (if not ($lines | any {|l| ($l | str starts-with $"profile ($name) ") and ($l | str contains " flags=(") }) {
                $"profiles/($name) has no 'profile ($name) ... flags=\(' line"
            })
        ]
    }
    let locals = basenames local | where $it not-in $rows.name
        | each { $"local/($in) extends no profile of profiles.conf" }
    $profiles | flatten | compact | append $locals
}

def parse-ok [file: path, work: path, etc: path]: nothing -> bool {
    let run = do {
        (^apparmor_parser --skip-kernel-load --skip-cache --base $etc -I $work -I $etc
            --features-file ($etc | path join abi 4.0) $file)
    } | complete
    print --stderr --no-newline $run.stderr
    # a name with a disable/ link is skipped with exit 0, never parsed
    $run.exit_code == 0 and not ($run.stderr | str contains "Skipping profile")
}

def compile-check [rows: table, source: path, etc: path]: nothing -> list<string> {
    let upstream = glob $"($source)/**/*" --no-dir | where not ($it =~ '/(abstractions|tunables)/') | path basename
    let own = basenames profiles
    let names = $rows | get name | each {|n|
        if $n in $own {
            if $n in $upstream and $n not-in $OVERRIDES { $"apparmor.d now ships ($n), drop profiles/($n)" }
        } else if $n not-in $upstream { $"apparmor.d has no profile named ($n)" }
    } | compact
    let work = mktemp -d
    mkdir ($work | path join abstractions dotfiles) ($work | path join local)
    glob abstractions/* | each { cp $in ($work | path join abstractions dotfiles) } | ignore
    glob local/* | each { cp $in ($work | path join local) } | ignore
    # parsed under the installed name: the bare one has a disable/ link wherever a stock stub exists
    let profiles = $own | each {|n|
        let file = $work | path join $"($n)($OWN_SUFFIX)"
        cp $"profiles/($n)" $file
        if not (parse-ok $file $work $etc) { $"profiles/($n) does not compile" }
    } | compact
    # an own profile above already pulled in its local from $work; apparmor.d deploys one that replaces a stock
    # profile as <name>.apparmor.d
    let locals = basenames local | where $it not-in $own | each {|n|
        let target = [$"($n).apparmor.d" $n] | each {|f| $etc | path join $f }
            | where ($it | path exists) and ($it | path expand | path type) == file | get --optional 0
        if $target == null {
            print --stderr $"apparmor.test: skipped local/($n): no ($n) profile in ($etc)"
        } else if not (parse-ok $target $work $etc) {
            $"($target | path basename) does not compile with local/($n)"
        }
    } | compact
    rm -rf $work
    $names ++ $profiles ++ $locals
}

def required-check []: nothing -> list<string> {
    $REQUIRED_RULES | items {|name, rules|
        let have = open --raw $"local/($name)" | lines | str trim
        $rules | where $it not-in $have | each {|r| $"local/($name) lacks '($r)'" }
    } | flatten
}

# An override differs from its upstream apparmor.d profile only in the profile line.
def override-check [source: path]: nothing -> list<string> {
    let body = {|text| $text | lines | where not ($it =~ '^profile ') }
    $OVERRIDES | each {|n|
        let upstream = glob $"($source)/**/($n)" --no-dir | where not ($it =~ '/(abstractions|tunables)/') | get --optional 0
        if $upstream == null { return $"apparmor.d no longer ships ($n), profiles/($n) has nothing to follow" }
        let own = open --raw $"profiles/($n)" | lines
        let header = $own | take while { $in != "" } | length
        let ours = $own | skip ($header + 1) | str join "\n"
        if (do $body $ours) != (do $body (open --raw $upstream)) {
            $"profiles/($n) drifted from ($upstream): re-sync it, keeping only its profile line"
        }
    } | compact
}

def main []: nothing -> nothing {
    cd $HERE
    let source = $env.APPARMOR_D_SRC? | default /usr/share/apparmor.d
    let etc = $env.APPARMOR_ETC? | default /etc/apparmor.d
    let rows = open --raw profiles.conf | lines | where { $in =~ '^[^#]' and ($in | str trim) != "" }
        | parse --regex '^(?<name>\S+)\s*(?<mode>\S*)\s*(?<extra>.*)$'
    let compilable = (
        ($source | path exists) and ($etc | path join abstractions base-strict | path exists)
        and (which apparmor_parser | is-not-empty)
    )
    let compiled = if $compilable { compile-check $rows $source $etc } else {
        let needs = $"($source), ($etc)/abstractions/base-strict and apparmor_parser"
        print --stderr $"apparmor.test: skipped compiling: needs ($needs)"
        []
    }
    let drifted = if ($source | path exists) { override-check $source } else {
        print --stderr $"apparmor.test: skipped the override check: no ($source)"
        []
    }
    let failures = (rows-check $rows) ++ (own-check $rows) ++ (required-check) ++ $compiled ++ $drifted
    for f in $failures { print --stderr $"apparmor.test: ($f)" }
    if ($failures | is-not-empty) { exit 1 }
}
