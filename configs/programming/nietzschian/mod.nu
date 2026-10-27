use module.nu *

# nietzschian-debugger: a Claude-driven CLI that answers a bug with questions, never the fix. BYOK, reads
# ANTHROPIC_API_KEY from the environment; the owner sets that key, this module only installs the tool.
export const meta = {packages: {pacman: [uv]}}

const URL = "https://github.com/DilawarShafiq/nietzschian-debugger"
# v0.1.0; the commit pins the tool, --exclude-newer freezes its floating deps (anthropic, click, rich)
const COMMIT = "94e452d3fc83acb6360ac2918562961766c9753a"
const FROZEN = "2026-10-27"

def pin []: nothing -> string {
    $"($COMMIT) ($FROZEN)"
}

def pin-file []: nothing -> path {
    ^uv tool dir | str trim | path join nietzschian-debugger .dotfiles-pin
}

export def link [cfg: record] {
    if (which uv | is-empty) { return [] }
    let installed = try { open --raw (pin-file) | str trim } catch { "" }
    if $installed == (pin) { return [] }
    [(step install)]
}

export def install []: nothing -> nothing {
    ^uv tool install -q --force --exclude-newer $FROZEN $"nietzschian-debugger @ git+($URL)@($COMMIT)"
    pin | save --force (pin-file)
}
