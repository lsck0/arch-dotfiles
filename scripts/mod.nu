# Links every scripts/*.nu but mod.nu and tests, and each *.sh without a .nu twin, into ~/.local/bin, out of root's
# secure_path.

use module.nu *

export def link [cfg: record] {
    let nus = glob *.nu | where {|s| ($s | path basename) != "mod.nu" and not ($s | str ends-with ".test.nu") }
    let shells = glob *.sh | where {|s| not ($s | str replace --regex '\.sh$' '.nu' | path exists) }
    link-commands ...($nus ++ $shells | sort)
}
