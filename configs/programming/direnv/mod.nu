use module.nu *

export const meta = {
    packages: {nix: [devenv]}
    inputs: [~/.nix-profile/bin/devenv]
}

export def link [cfg: record] {
    # dot apply --packages puts devenv in the nix profile, which may not be on PATH yet
    let devenv = which devenv | get --optional 0.path | default ($nu.home-dir | path join .nix-profile bin devenv)
    if (which direnv | is-empty) or not ($devenv | path exists) { return [] }
    file-text (xdg config direnv direnvrc) $"(^$devenv direnvrc)\n"
}
