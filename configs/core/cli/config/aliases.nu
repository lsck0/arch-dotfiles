alias e = eza
alias l = eza -lh
alias la = eza -lah
alias ll = eza -lh
alias ls = eza
alias lt = eza -lah --tree
def ljournal [...args] { lazyjournal -T (date now | format date "%:z") ...$args }

# z and zi come from the zoxide init config.nu sources only when it exists; an alias cannot sit under an if, so the
# same parse-time check picks whether this module is used
module zoxide-aliases {
    export alias cd = z
    export alias cdi = zi
}
const ZOXIDE_ALIASES = if ($nu.cache-dir | path join zoxide.nu | path exists) { "zoxide-aliases" }
use $ZOXIDE_ALIASES *
