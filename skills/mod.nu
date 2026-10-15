use module.nu *

# every skills/l-*/ for each installed agent; gemini has its own registry, the others read a symlink
const TOOLS = {claude: ".claude", copilot: ".copilot", hermes: ".hermes"}

def skill-dirs []: nothing -> list<path> {
    glob l-* | where ($it | path type) == dir
}

export def link [cfg: record] {
    let dirs = skill-dirs
    let links = $TOOLS | items {|tool, home|
        if (which $tool | is-empty) { return [] }
        let base = $nu.home-dir | path join $home skills
        $dirs | each {|d| file-link $d ($base | path join ($d | path basename)) }
    } | flatten
    $links ++ [(step "gemini-register")]
}

# gemini drops recursive l-*/l-* symlinks into the tree; clear them so git never tracks them
export def gemini-register [] {
    recursive-links-clear
    if (which gemini | is-not-empty) {
        let linked = ^gemini skills list | complete | get stdout
        for d in (skill-dirs) {
            let name = $d | path basename
            if not ($linked | lines | any { $in == $"($name) [Enabled]" }) {
                # it prints a consent banner per skill; only a failure is worth showing
                let run = ^gemini skills link $d --scope user --consent | complete
                if $run.exit_code != 0 { error make {msg: $"gemini skills link ($name): ($run.stdout)($run.stderr)"} }
            }
        }
    }
    recursive-links-clear
}

def recursive-links-clear []: nothing -> nothing {
    glob l-*/l-* | where ($it | path type) == symlink | each { rm $in } | ignore
    let tracked = ^git ls-files -- l-*/l-* | lines | where $it != ""
    if ($tracked | is-not-empty) { ^git rm -q --cached ...$tracked }
}
