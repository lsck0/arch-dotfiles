$env.DO_NOT_TRACK = "1"
$env.EDITOR = "nvim"
$env.VISUAL = "nvim"
$env.SHELL = $nu.current-exe
$env.GOPATH = $"($env.HOME)/.go"
$env.ZSH_DISABLE_COMPFIX = "true"

$env.PATH = (
    $env.PATH
    | split row (char esep)
    | prepend [
        $"($env.HOME)/.cargo/bin"
        $"($env.HOME)/.ghcup/bin"
        $"($env.HOME)/.go/bin"
        $"($env.HOME)/.jai/bin"
        $"($env.HOME)/.local/bin"
    ]
    | uniq
    | where { |p| $p != "" }
)

$env.NU_VENDOR_DIR = $"($env.HOME)/.cache/nushell"
