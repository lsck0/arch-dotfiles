# Links every scripts/*.nu, and each *.sh without a .nu twin, into ~/.local/bin, out of root's secure_path.

use module.nu *

export def link [cfg: record] {
    let nus = glob *.nu | where ($it | path basename) != "mod.nu"
    let shells = glob *.sh | where {|s| not ($s | str replace --regex '\.sh$' '.nu' | path exists) }
    link-commands ...($nus ++ $shells | sort)
}
