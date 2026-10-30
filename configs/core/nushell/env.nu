$env.EDITOR = "nvim"
$env.VISUAL = "nvim"
$env.SHELL = $nu.current-exe
$env.DOTFILES = ($env.DOTFILES? | default ($nu.home-dir | path join projects arch-dotfiles))
# the generic pinentry (wsl, headless) finds the terminal through it, as zshrc's GPG_TTY
if (is-terminal --stdin) { $env.GPG_TTY = (^tty | str trim) }

$env.PATH = (
    $env.PATH
    | split row (char esep)
    | prepend $"($env.HOME)/.local/bin"
    | append [
        $"($env.HOME)/.cargo/bin"
        $"($env.HOME)/.ghcup/bin"
        ($env.GOPATH? | default $"($env.HOME)/.local/share/go" | path join bin)
        $"($env.HOME)/.jai/bin"
    ]
    | uniq
    | where { |p| $p != "" }
)
