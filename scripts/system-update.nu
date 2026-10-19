#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib usage.nu) [die]

const INSTALL_LOGGED_FAILURE = 1
const NVIM_TREESITTER_TIMEOUT_MS = 600000
const EMACS_UPGRADE = "(progn (require 'package)
  (setq package-archives '((\"gnu\" . \"https://elpa.gnu.org/packages/\")
                            (\"nongnu\" . \"https://elpa.nongnu.org/nongnu/\")
                            (\"melpa\" . \"https://melpa.org/packages/\")))
  (package-initialize)
  (package-refresh-contents)
  (package-upgrade-all))"

def has [command: string]: nothing -> bool { which $command | is-not-empty }

# Update packages, config, toolchains and editor plugins after a confirmation.
def main []: nothing -> nothing {
    cd ($SCRIPTS | path dirname)
    if ($env.DIRENV_DIR? | is-not-empty) { die "run outside a direnv directory" }
    print "ARE U SURE?"
    if (input "Type 'y' to continue: ") != "y" {
        print "Aborting update."
        exit 1
    }
    let dot = $SCRIPTS | path join dot.nu
    try { ^nu --no-config-file $dot apply --packages } catch {|err| if $err.exit_code? != $INSTALL_LOGGED_FAILURE { exit 1 } }
    try { ^nu --no-config-file $dot apply } catch { print --stderr "system-update: dot apply finished with failures, see FAILURES.config" }
    if (has flatpak) { ^flatpak update --assumeyes }
    if (has rustup) { ^rustup update }
    if (has opam) {
        ^opam update
        ^opam upgrade -y
    }
    if (has ghcup) {
        ^ghcup upgrade
        [cabal ghc hls stack] | each { ^ghcup install $in latest } | ignore
    }
    # interactive: plugins.nu sudo's, which only a terminal can answer on a FIDO2-sudo box
    if ($env.HYPRLAND_INSTANCE_SIGNATURE? | is-not-empty) and (has hyprpm) {
        ^./configs/desktop/hyprland/plugins.nu
    }
    if (has tldr) { ^tldr --update_cache }
    if (has nvim) {
        (^nvim --headless "+Lazy! sync" +MasonUpdate +MasonToolsUpdateSync "+MasonInstall glsl_analyzer"
            $"+lua require\('nvim-treesitter'\).update\(\):wait\(($NVIM_TREESITTER_TIMEOUT_MS)\)" +qa)
    }
    if (has emacs) { ^emacs --batch --eval $EMACS_UPGRADE }
}
