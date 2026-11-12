use module.nu *

const TOOLS = {claude: ".claude", copilot: ".copilot", gemini: ".gemini", hermes: ".hermes"}

export def link [cfg: record] {
    let dirs = glob l-* | where ($it | path type) == dir
    $TOOLS | items {|tool, home|
        if (which $tool | is-not-empty) {
            $dirs | each {|d| file-link $d ($nu.home-dir | path join $home skills ($d | path basename)) }
        }
    }
}
