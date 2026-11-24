alias downgrade = sudo-at-terminal downgrade

# pacman under sudo only for what changes the system, so queries need no fido touch; same letters as aliases.zsh's pacman
def --wrapped pacman [...rest] {
    let long = {
        --query: Q --deptest: T --version: V --help: h --sync: S --files: F --search: s --info: i --groups: g
        --list: l --print: p --refresh: y --sysupgrade: u --clean: c --downloadonly: w
    }
    let ops = ($rest | take until {|a| $a == "--" } | each {|a|
        if ($a | str starts-with "--") { $long | get -o $a | default "" } else if ($a =~ '^-.') { $a | str substring 1.. } else { "" }
    } | str join)
    let unprivileged = ($ops =~ '[QTVh]') or ($ops =~ 'F' and $ops !~ 'y') or ($ops =~ 'S' and $ops =~ '[siglp]' and $ops !~ '[yucw]')
    if $unprivileged { ^pacman ...$rest } else { sudo-at-terminal pacman ...$rest }
}
