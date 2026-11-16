use module.nu *

# nietzschian-debugger: a Claude-driven CLI that answers a bug with questions, never the fix. BYOK, reads
# ANTHROPIC_API_KEY from the environment; the owner sets that key, this module only installs the tool.
export const meta = {packages: {pacman: [uv]}}

const URL = "https://github.com/DilawarShafiq/nietzschian-debugger"
# v0.5.2, 2026-10-28; the commit pins the tool, --exclude-newer freezes its floating deps (anthropic, click, rich)
const COMMIT = "b71b3c7f00652159d689fdcaa2ebc06bb6aeca55"
const FROZEN = "2026-10-28"
const PIN = $"($COMMIT) ($FROZEN)"

# the stamp the install was tracked by before it was recorded: one matching the pin proves it already ran
def pin-file []: nothing -> path {
    ^uv tool dir | str trim | path join nietzschian-debugger .dotfiles-pin
}

export def link [cfg: record] {
    if (which uv | is-empty) { return [] }
    let installed = file-trim (pin-file)
    [(step install --key $PIN --done=($installed == $PIN) --undo [uv tool uninstall nietzschian-debugger] --network)]
}

export def install []: nothing -> nothing {
    ^uv tool install -q --force --exclude-newer $FROZEN $"nietzschian-debugger @ git+($URL)@($COMMIT)"
}
