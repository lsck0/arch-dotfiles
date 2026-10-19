use module.nu *

# a links.txt line is `<url>` (named after the host minus its last label) or `<url> as <name>`
const NAME_PATTERN = '^[A-Za-z0-9_-]+$'

def parse-links []: nothing -> table {
    # a comment starts the line or follows whitespace, so a url's #fragment stays
    open links.txt | lines | each { str replace --regex '(^|\s)#.*$' '' | str trim } | where $it != "" | each {|line|
        let parts = $line | split row --regex '\s+'
        let url = $parts | first
        if not ($url starts-with "http://" or $url starts-with "https://") {
            error make {msg: $"links.txt: '($url)' is not an http\(s\) url"}
        }
        let name = match ($parts | length) {
            1 => {
                let host = $url | parse --regex '^https?://(?<h>[^/?#]+)' | get 0.h | split row "@" | last | split row ":" | first | str lowercase
                if ($host | str contains ".") { $host | str replace --regex '\.[^.]+$' '' } else { $host }
            }
            3 if ($parts | get 1) == "as" => ($parts | get 2)
            _ => { error make {msg: $"links.txt: '($line)' is not '<url>' or '<url> as <name>'"} }
        }
        if not ($name =~ $NAME_PATTERN) {
            error make {msg: $"links.txt: '($name)' for ($url) is not a command name ($NAME_PATTERN)"}
        }
        {name: $name, url: $url}
    }
}

export def link [cfg: record] {
    let links = parse-links
    let bin = $nu.home-dir | path join .local bin
    let commands = $links | each {|l| file-text ($bin | path join $l.name) $"#!/bin/sh\nexec xdg-open '($l.url)'\n" --mode "755" }
    $commands ++ [(file-text ($env.DOTFILES | path join weblinks collection links.js) $"const weblinks = ($links | to json --raw);\n")]
}
