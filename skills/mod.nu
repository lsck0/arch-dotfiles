use module.nu *

const TOOLS = {claude: ".claude", copilot: ".copilot", gemini: ".gemini", hermes: ".hermes"}

# The l-* skills are the owner's style, workflow and machine; another login gets none.
export def link [cfg: record] {
    if not (profile-has secrets) { return [] }
    let dirs = glob l-* | where ($it | path type) == dir
    $TOOLS | items {|tool, home|
        if (which $tool | is-not-empty) {
            $dirs | each {|d| file-link $d ($nu.home-dir | path join $home skills ($d | path basename)) }
        }
    }
}
