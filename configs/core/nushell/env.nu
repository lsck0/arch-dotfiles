$env.EDITOR = "nvim"
$env.VISUAL = "nvim"
$env.SHELL = $nu.current-exe
$env.DOTFILES = ($env.DOTFILES? | default ($nu.home-dir | path join projects arch-dotfiles))
# the generic pinentry (wsl, headless) finds the terminal through it, as zshrc's GPG_TTY
if (is-terminal --stdin) { $env.GPG_TTY = (^tty | str trim) }

$env.PATH = (
    $env.PATH
    | split row (char esep)
    | prepend ($nu.home-dir | path join .local bin)
    | append [
        ($nu.home-dir | path join .cargo bin)
        ($nu.home-dir | path join .ghcup bin)
        ($env.GOPATH? | default ($nu.home-dir | path join .local share go) | path join bin)
        ($nu.home-dir | path join .jai bin)
    ]
    | uniq
    | where { |p| $p != "" }
)
