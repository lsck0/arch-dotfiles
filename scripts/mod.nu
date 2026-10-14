use module.nu *

# every scripts/*.nu and any not-yet-ported *.sh as a command in ~/.local/bin; user scripts stay out of root's
# secure_path. a command whose script was ported or removed leaves a dangling link the full-run sweep prunes
export def link [cfg: record] {
    let nus = glob *.nu | where ($it | path basename) != "mod.nu"
    let shells = glob *.sh | where {|s| not ($s | str replace --regex '\.sh$' '.nu' | path exists) }
    link-commands ...($nus ++ $shells | sort)
}
