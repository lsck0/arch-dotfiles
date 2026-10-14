use module.nu *

# user scripts stay out of root's secure_path; a removed script's dangling link is pruned by the full-run sweep
export def link [cfg: record] {
    let nus = glob *.nu | where ($it | path basename) != "mod.nu"
    let shells = glob *.sh | where {|s| not ($s | str replace --regex '\.sh$' '.nu' | path exists) }
    link-commands ...($nus ++ $shells | sort)
}
