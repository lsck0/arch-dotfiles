use module.nu *

const TOOLS = {claude: ".claude", copilot: ".copilot", gemini: ".gemini", hermes: ".hermes"}

def skill-dirs []: nothing -> list<path> {
    glob l-* | where ($it | path type) == dir
}

export def link [cfg: record] {
    let dirs = skill-dirs
    $TOOLS | items {|tool, home|
        if (which $tool | is-empty) { return [] }
        let base = $nu.home-dir | path join $home skills
        $dirs | each {|d| file-link $d ($base | path join ($d | path basename)) }
    } | flatten
}
