alias e = eza
alias l = eza -lh
alias la = eza -lah
alias ls = eza
alias lt = eza -lah --tree
def ljournal [...args] { lazyjournal -T (date now | format date "%:z") ...$args }
# z and zi come from the zoxide init config.nu sources
alias cd = z
alias cdi = zi
