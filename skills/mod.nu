use module.nu *

const TOOLS = {claude: ".claude", copilot: ".copilot", gemini: ".gemini", hermes: ".hermes"}

# The skills for this repo. They name the owner's machine, so another login gets none; the owner's style, personas and
# workflows are configs/secrets/skills.
export def link [cfg: record] {
    if not (profile-has secrets) { return [] }
    let dirs = glob l-* | where ($it | path type) == dir
    $TOOLS | items {|tool, home|
        if (which $tool | is-not-empty) {
            $dirs | each {|d| file-link $d ($nu.home-dir | path join $home skills ($d | path basename)) }
        }
    }
}
